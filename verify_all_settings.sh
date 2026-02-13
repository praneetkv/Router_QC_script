#!/bin/bash

##############################################
# GL.iNet Router Full Verification Script
# Checks all critical router settings
# Logs results to CSV for QC tracking
##############################################

# Router connection settings
ROUTER_IP="172.16.1.1"
ROUTER_PASSWORD="MusterLegoWaking"

# CSV log file (same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CSV_LOG="${SCRIPT_DIR}/router_qc_log.csv"

# Status file (for desktop launcher to read)
STATUS_FILE="/tmp/verify_router_status"
rm -f "$STATUS_FILE"

# Expected values
EXPECTED_LAN_IP="172.16.1.1"
EXPECTED_DHCP_START="100"
EXPECTED_DHCP_LIMIT="150"
EXPECTED_GOODCLOUD="1"
EXPECTED_WIFI_DISABLED="1"
EXPECTED_RTTY_SSH="1"
EXPECTED_RTTY_WEB="1"
EXPECTED_RESET_SOFT="10"
EXPECTED_RESET_HARD="120"
EXPECTED_LED_SOFT_ON="250"
EXPECTED_LED_SOFT_OFF="250"
EXPECTED_LED_HARD_ON="125"
EXPECTED_LED_HARD_OFF="125"

# Counters
PASS=0
FAIL=0

# Per-test results (PASS/FAIL)
R_CONNECTIVITY=""
R_LAN_IP=""
R_DHCP_START=""
R_DHCP_LIMIT=""
R_INTERNET_GOOGLE=""
R_INTERNET_CLOUDFLARE=""
R_GOODCLOUD=""
R_WIFI_2G=""
R_WIFI_5G=""
R_RTTY_SSH=""
R_RTTY_WEB=""
R_RESET_SOFT=""
R_RESET_HARD=""
R_LED_SOFT_ON=""
R_LED_SOFT_OFF=""
R_LED_HARD_ON=""
R_LED_HARD_OFF=""

echo "=========================================="
echo "GL.iNet Router Full Verification"
echo "=========================================="
echo ""
echo "Router IP: $ROUTER_IP"
echo "Password: $ROUTER_PASSWORD"
echo ""

# SSH options
SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Function to run SSH command
ssh_cmd() {
    if [ "$SSH_AUTH_METHOD" = "key" ]; then
        ssh $SSH_OPTS root@$ROUTER_IP "$1" 2>/dev/null
    else
        sshpass -p "$ROUTER_PASSWORD" ssh $SSH_OPTS root@$ROUTER_IP "$1" 2>/dev/null
    fi
}

# Setup SSH authentication
setup_ssh() {
    echo "Checking SSH key authentication..."

    if ssh $SSH_OPTS -o BatchMode=yes root@$ROUTER_IP "echo ok" 2>/dev/null | grep -q "ok"; then
        SSH_AUTH_METHOD="key"
        echo "  [OK] SSH key authentication already working"
        return 0
    fi

    if command -v sshpass &>/dev/null; then
        if sshpass -p "$ROUTER_PASSWORD" ssh $SSH_OPTS root@$ROUTER_IP "echo ok" 2>/dev/null | grep -q "ok"; then
            SSH_AUTH_METHOD="sshpass"
            echo "  [OK] SSH password authentication working (via sshpass)"
            return 0
        fi
    fi

    echo "  SSH key auth not set up. Setting up now..."
    echo ""

    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        echo "  Generating SSH key..."
        mkdir -p "$HOME/.ssh"
        ssh-keygen -t rsa -b 2048 -f "$HOME/.ssh/id_rsa" -N "" -q
        echo "  [OK] SSH key generated"
    fi

    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$ROUTER_IP" 2>/dev/null

    echo "  Enter router password ($ROUTER_PASSWORD) when prompted:"
    echo ""
    ssh-copy-id $SSH_OPTS root@$ROUTER_IP

    if ssh $SSH_OPTS -o BatchMode=yes root@$ROUTER_IP "echo ok" 2>/dev/null | grep -q "ok"; then
        SSH_AUTH_METHOD="key"
        echo ""
        echo "  [OK] SSH key authentication configured!"
        return 0
    else
        echo ""
        echo "  [FAIL] SSH key setup failed"
        return 1
    fi
}

# Function to check result and track per-test status
check_result() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    local var_name="$4"

    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $name: $actual"
        ((PASS++))
        eval "$var_name=PASS"
    else
        echo "  [FAIL] $name: $actual (expected: $expected)"
        ((FAIL++))
        eval "$var_name=FAIL"
    fi
}

# Run SSH key setup
if ! setup_ssh; then
    echo "Cannot proceed without SSH access."
    exit 1
fi
echo ""

# 1. Check connectivity
echo "[1/8] Checking Router Connectivity..."
echo "----------------------------------------"
if ping -c 2 -W 3 "$ROUTER_IP" > /dev/null 2>&1; then
    echo "  [PASS] Router reachable at $ROUTER_IP"
    ((PASS++))
    R_CONNECTIVITY="PASS"
else
    echo "  [FAIL] Router not reachable at $ROUTER_IP"
    ((FAIL++))
    R_CONNECTIVITY="FAIL"
    echo ""
    echo "Cannot continue without router connectivity."
    exit 1
fi
echo ""

# 2. Check LAN Configuration
echo "[2/8] Checking LAN Configuration..."
echo "----------------------------------------"
LAN_CONFIG=$(ssh_cmd "uci get network.lan.ipaddr 2>/dev/null")
check_result "LAN IP Address" "$EXPECTED_LAN_IP" "$LAN_CONFIG" "R_LAN_IP"

DHCP_START=$(ssh_cmd "uci get dhcp.lan.start 2>/dev/null")
check_result "DHCP Start" "$EXPECTED_DHCP_START" "$DHCP_START" "R_DHCP_START"

DHCP_LIMIT=$(ssh_cmd "uci get dhcp.lan.limit 2>/dev/null")
check_result "DHCP Limit" "$EXPECTED_DHCP_LIMIT" "$DHCP_LIMIT" "R_DHCP_LIMIT"
echo ""

# 3. Check Internet Connectivity
echo "[3/8] Checking Internet Connectivity..."
echo "----------------------------------------"
GOOGLE_CHECK=$(ssh_cmd "ping -c 2 -W 5 8.8.8.8 > /dev/null 2>&1 && echo 'yes' || echo 'no'")
CLOUDFLARE_CHECK=$(ssh_cmd "ping -c 2 -W 5 1.1.1.1 > /dev/null 2>&1 && echo 'yes' || echo 'no'")

if [ "$GOOGLE_CHECK" = "yes" ]; then
    echo "  [PASS] 8.8.8.8 (Google DNS) reachable"
    ((PASS++))
    R_INTERNET_GOOGLE="PASS"
else
    echo "  [FAIL] 8.8.8.8 (Google DNS) not reachable"
    ((FAIL++))
    R_INTERNET_GOOGLE="FAIL"
fi

if [ "$CLOUDFLARE_CHECK" = "yes" ]; then
    echo "  [PASS] 1.1.1.1 (Cloudflare DNS) reachable"
    ((PASS++))
    R_INTERNET_CLOUDFLARE="PASS"
else
    echo "  [FAIL] 1.1.1.1 (Cloudflare DNS) not reachable"
    ((FAIL++))
    R_INTERNET_CLOUDFLARE="FAIL"
fi

if [ "$GOOGLE_CHECK" = "yes" ] || [ "$CLOUDFLARE_CHECK" = "yes" ]; then
    echo "  [INFO] Internet connectivity confirmed via SIM1"
else
    echo "  [WARN] Internet may be down or both servers blocked"
fi
echo ""

# 4. Check GoodCloud Configuration
echo "[4/8] Checking GoodCloud Configuration..."
echo "----------------------------------------"
GOODCLOUD_ENABLED=$(ssh_cmd "uci get gl-cloud.@cloud[0].enable 2>/dev/null")
check_result "GoodCloud Enabled" "$EXPECTED_GOODCLOUD" "$GOODCLOUD_ENABLED" "R_GOODCLOUD"
echo ""

# 5. Check WiFi Configuration
echo "[5/8] Checking WiFi Configuration..."
echo "----------------------------------------"
WIFI_DISABLED_0=$(ssh_cmd "uci get wireless.wifi0.disabled 2>/dev/null")
WIFI_DISABLED_1=$(ssh_cmd "uci get wireless.wifi1.disabled 2>/dev/null")

if [ "$WIFI_DISABLED_0" = "1" ]; then
    echo "  [PASS] WiFi radio0 (2.4GHz) disabled: $WIFI_DISABLED_0"
    ((PASS++))
    R_WIFI_2G="PASS"
else
    echo "  [FAIL] WiFi radio0 (2.4GHz) disabled: ${WIFI_DISABLED_0:-0} (expected: 1)"
    ((FAIL++))
    R_WIFI_2G="FAIL"
fi

if [ "$WIFI_DISABLED_1" = "1" ]; then
    echo "  [PASS] WiFi radio1 (5GHz) disabled: $WIFI_DISABLED_1"
    ((PASS++))
    R_WIFI_5G="PASS"
else
    echo "  [FAIL] WiFi radio1 (5GHz) disabled: ${WIFI_DISABLED_1:-0} (expected: 1)"
    ((FAIL++))
    R_WIFI_5G="FAIL"
fi
echo ""

# 6. Check SSH/Web Remote Access (RTTY)
echo "[6/8] Checking Remote Access (RTTY)..."
echo "----------------------------------------"
RTTY_SSH=$(ssh_cmd "uci get rtty.general.ssh_en 2>/dev/null")
RTTY_WEB=$(ssh_cmd "uci get rtty.general.web_en 2>/dev/null")
check_result "RTTY SSH Access" "$EXPECTED_RTTY_SSH" "$RTTY_SSH" "R_RTTY_SSH"
check_result "RTTY Web Access" "$EXPECTED_RTTY_WEB" "$RTTY_WEB" "R_RTTY_WEB"
echo ""

# 7. Check Reset Button Timing
echo "[7/8] Checking Reset Button Timing..."
echo "----------------------------------------"
RESET_SCRIPT=$(ssh_cmd "cat /etc/rc.button/reset 2>/dev/null")

if [ -n "$RESET_SCRIPT" ]; then
    FOUND_SOFT=$(echo "$RESET_SCRIPT" | grep "^SOFT_TIME=" | head -1 | sed 's/SOFT_TIME=//' | sed 's/#.*//' | tr -d ' ')
    FOUND_HARD=$(echo "$RESET_SCRIPT" | grep "^HARD_TIME=" | head -1 | sed 's/HARD_TIME=//' | sed 's/#.*//' | tr -d ' ')

    check_result "Soft Reset Time (seconds)" "$EXPECTED_RESET_SOFT" "$FOUND_SOFT" "R_RESET_SOFT"
    check_result "Hard Reset Time (seconds)" "$EXPECTED_RESET_HARD" "$FOUND_HARD" "R_RESET_HARD"
else
    echo "  [FAIL] Reset button script not found"
    ((FAIL++))
    ((FAIL++))
    R_RESET_SOFT="FAIL"
    R_RESET_HARD="FAIL"
fi
echo ""

# 8. Check LED Blink Patterns
echo "[8/8] Checking LED Blink Patterns..."
echo "----------------------------------------"
if [ -n "$RESET_SCRIPT" ]; then
    FOUND_LED_SOFT_ON=$(echo "$RESET_SCRIPT" | grep "SOFT_LED_ON=" | head -1 | sed 's/.*SOFT_LED_ON=//' | tr -d ' ')
    FOUND_LED_SOFT_OFF=$(echo "$RESET_SCRIPT" | grep "SOFT_LED_OFF=" | head -1 | sed 's/.*SOFT_LED_OFF=//' | tr -d ' ')
    FOUND_LED_HARD_ON=$(echo "$RESET_SCRIPT" | grep "HARD_LED_ON=" | head -1 | sed 's/.*HARD_LED_ON=//' | tr -d ' ')
    FOUND_LED_HARD_OFF=$(echo "$RESET_SCRIPT" | grep "HARD_LED_OFF=" | head -1 | sed 's/.*HARD_LED_OFF=//' | tr -d ' ')

    check_result "LED Soft ON (ms)" "$EXPECTED_LED_SOFT_ON" "$FOUND_LED_SOFT_ON" "R_LED_SOFT_ON"
    check_result "LED Soft OFF (ms)" "$EXPECTED_LED_SOFT_OFF" "$FOUND_LED_SOFT_OFF" "R_LED_SOFT_OFF"
    check_result "LED Hard ON (ms)" "$EXPECTED_LED_HARD_ON" "$FOUND_LED_HARD_ON" "R_LED_HARD_ON"
    check_result "LED Hard OFF (ms)" "$EXPECTED_LED_HARD_OFF" "$FOUND_LED_HARD_OFF" "R_LED_HARD_OFF"
else
    echo "  [FAIL] Reset button script not found - cannot check LED patterns"
    ((FAIL++))
    ((FAIL++))
    ((FAIL++))
    ((FAIL++))
    R_LED_SOFT_ON="FAIL"
    R_LED_SOFT_OFF="FAIL"
    R_LED_HARD_ON="FAIL"
    R_LED_HARD_OFF="FAIL"
fi
echo ""

# Device Information
echo "=========================================="
echo "Device Information:"
echo "=========================================="
HOSTNAME=$(ssh_cmd "uci get system.@system[0].hostname 2>/dev/null" || echo "N/A")
DEVICE_MODEL=$(ssh_cmd "cat /tmp/sysinfo/model 2>/dev/null" || echo "N/A")
DEVICE_ID=$(ssh_cmd "cat /proc/gl-hw-info/device_ddns 2>/dev/null" || echo "N/A")
DEVICE_SN=$(ssh_cmd "cat /proc/gl-hw-info/device_sn 2>/dev/null" || echo "N/A")
DEVICE_MAC=$(ssh_cmd "cat /proc/gl-hw-info/device_mac 2>/dev/null" || echo "N/A")

# Get modem bus and retrieve IMEI/ICCID
MODEM_BUS=$(ssh_cmd "cat /proc/gl-hw-info/build-in-modem 2>/dev/null")
if [ -n "$MODEM_BUS" ]; then
    DEVICE_IMEI=$(ssh_cmd "gl_modem -B $MODEM_BUS AT AT+CGSN 2>/dev/null" | grep -oE '^[0-9]{15}')
    DEVICE_ICCID=$(ssh_cmd "gl_modem -B $MODEM_BUS AT AT+QCCID 2>/dev/null" | grep -oE '[0-9]{19,20}')
fi

echo "  Hostname: ${HOSTNAME:-N/A}"
echo "  Model: ${DEVICE_MODEL:-N/A}"
echo "  Device ID: ${DEVICE_ID:-N/A}"
echo "  Serial Number: ${DEVICE_SN:-N/A}"
echo "  MAC Address: ${DEVICE_MAC:-N/A}"
echo "  IMEI: ${DEVICE_IMEI:-N/A}"
echo "  ICCID: ${DEVICE_ICCID:-N/A}"
echo ""

# Summary
echo "=========================================="
echo "VERIFICATION SUMMARY"
echo "=========================================="
echo ""
TOTAL=$((PASS + FAIL))
echo "  Passed: $PASS / $TOTAL"
echo "  Failed: $FAIL / $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    OVERALL_STATUS="ALL PASSED"
else
    OVERALL_STATUS="FAILED"
fi

# ---- Write CSV row ----
CSV_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
GC_DEVICE_NAME=""
GC_CLOUD_STATUS=""

# Write header if file doesn't exist
if [ ! -f "$CSV_LOG" ]; then
    echo "Timestamp,MAC_Address,Serial_Number,Device_ID,IMEI,ICCID,Hostname,Model,Connectivity,LAN_IP,DHCP_Start,DHCP_Limit,Internet_Google,Internet_Cloudflare,GoodCloud_Enabled,WiFi_2.4GHz_Off,WiFi_5GHz_Off,RTTY_SSH,RTTY_Web,Reset_Soft,Reset_Hard,LED_Soft_ON,LED_Soft_OFF,LED_Hard_ON,LED_Hard_OFF,Passed,Failed,Total,Overall_Status,GoodCloud_Name,GoodCloud_Online" > "$CSV_LOG"
fi

if [ $FAIL -ne 0 ]; then
    echo "  STATUS: SOME CHECKS FAILED"
    echo ""
    echo "  Fix the above failures before registering on GoodCloud."
    echo "  Skipping GoodCloud registration."

    # Log to CSV even on failure
    echo "\"$CSV_TIMESTAMP\",\"${DEVICE_MAC:-N/A}\",\"${DEVICE_SN:-N/A}\",\"${DEVICE_ID:-N/A}\",\"${DEVICE_IMEI:-N/A}\",\"${DEVICE_ICCID:-N/A}\",\"${HOSTNAME:-N/A}\",\"${DEVICE_MODEL:-N/A}\",\"$R_CONNECTIVITY\",\"$R_LAN_IP\",\"$R_DHCP_START\",\"$R_DHCP_LIMIT\",\"$R_INTERNET_GOOGLE\",\"$R_INTERNET_CLOUDFLARE\",\"$R_GOODCLOUD\",\"$R_WIFI_2G\",\"$R_WIFI_5G\",\"$R_RTTY_SSH\",\"$R_RTTY_WEB\",\"$R_RESET_SOFT\",\"$R_RESET_HARD\",\"$R_LED_SOFT_ON\",\"$R_LED_SOFT_OFF\",\"$R_LED_HARD_ON\",\"$R_LED_HARD_OFF\",$PASS,$FAIL,$TOTAL,\"$OVERALL_STATUS\",\"\",\"\"" >> "$CSV_LOG"

    echo ""
    echo "  [OK] Results logged to $CSV_LOG"
    echo ""

    # Write status for desktop launcher
    echo "RESULT=FAIL" > "$STATUS_FILE"
    echo "PASS_COUNT=$PASS" >> "$STATUS_FILE"
    echo "FAIL_COUNT=$FAIL" >> "$STATUS_FILE"
    echo "TOTAL=$TOTAL" >> "$STATUS_FILE"
    echo "MAC=${DEVICE_MAC:-N/A}" >> "$STATUS_FILE"
    echo "SN=${DEVICE_SN:-N/A}" >> "$STATUS_FILE"

    exit 1
fi

echo "  STATUS: ALL CHECKS PASSED - proceeding to GoodCloud registration"
echo ""

##############################################
# GoodCloud: Add device to virtusense org
##############################################

# GoodCloud config
GC_EMAIL="logcom@virtusense.com"
GC_PASSWORD="MusterLegoWaking"
GC_API="https://api.goodcloud.xyz"
GC_ORG_ID="d6268cca351035d902c9301bbfd8ed12"

# Check dependencies for GoodCloud
if ! command -v jq &>/dev/null; then
    echo "[WARN] jq not installed - skipping GoodCloud registration."

    echo "\"$CSV_TIMESTAMP\",\"${DEVICE_MAC:-N/A}\",\"${DEVICE_SN:-N/A}\",\"${DEVICE_ID:-N/A}\",\"${DEVICE_IMEI:-N/A}\",\"${DEVICE_ICCID:-N/A}\",\"${HOSTNAME:-N/A}\",\"${DEVICE_MODEL:-N/A}\",\"$R_CONNECTIVITY\",\"$R_LAN_IP\",\"$R_DHCP_START\",\"$R_DHCP_LIMIT\",\"$R_INTERNET_GOOGLE\",\"$R_INTERNET_CLOUDFLARE\",\"$R_GOODCLOUD\",\"$R_WIFI_2G\",\"$R_WIFI_5G\",\"$R_RTTY_SSH\",\"$R_RTTY_WEB\",\"$R_RESET_SOFT\",\"$R_RESET_HARD\",\"$R_LED_SOFT_ON\",\"$R_LED_SOFT_OFF\",\"$R_LED_HARD_ON\",\"$R_LED_HARD_OFF\",$PASS,$FAIL,$TOTAL,\"$OVERALL_STATUS\",\"jq missing\",\"\"" >> "$CSV_LOG"
    exit 0
fi

# RSA public key (GoodCloud frontend)
GC_RSA_PEM=$(mktemp /tmp/gc_rsa_XXXXXX.pem)
cat > "$GC_RSA_PEM" <<'GCPEM'
-----BEGIN PUBLIC KEY-----
MFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAItoR8lrBZ/ZaJZ3XvvgP8I31ImaTwbE
PzPElmIZAasWoAzw3InqMVyeL7rTlFS3TFz3HMKBnrFlr463Bu19Tz0CAwEAAQ==
-----END PUBLIC KEY-----
GCPEM

gc_rsa_encrypt() {
    echo -n "$1" | openssl rsautl -encrypt -pubin -inkey "$GC_RSA_PEM" 2>/dev/null | base64 -w 0
}

gc_api_call() {
    local method="$1" url="$2" token="$3" data="$4"
    local sig
    sig=$(gc_rsa_encrypt "$(date +%s%3N)")
    if [ "$method" = "GET" ]; then
        curl -s -X GET "${GC_API}${url}" -H "token: $token" -H "signature: $sig"
    else
        curl -s -X POST "${GC_API}${url}" -H "token: $token" -H "signature: $sig" \
            -H "Content-Type: application/json" -d "$data"
    fi
}

echo "=========================================="
echo "GoodCloud Registration (virtusense)"
echo "=========================================="
echo ""

# Normalize MAC for GoodCloud (no colons, lowercase)
GC_MAC=$(echo "$DEVICE_MAC" | tr -d ':' | tr '[:upper:]' '[:lower:]')

if [ "$DEVICE_ID" = "N/A" ] || [ "$GC_MAC" = "n/a" ] || [ "$DEVICE_SN" = "N/A" ]; then
    echo "  [SKIP] Missing device info - cannot register."
    rm -f "$GC_RSA_PEM"
    exit 0
fi

# Login to GoodCloud
echo "  Logging in to GoodCloud..."
GC_ENC_PW=$(gc_rsa_encrypt "$GC_PASSWORD")
GC_FP=$(echo -n "${GC_EMAIL}$(date +%s%N)" | md5sum | cut -d' ' -f1)

GC_LOGIN=$(curl -s -X POST "${GC_API}/cloud-basic/cloud/v2/auth/login" \
    -F "name=${GC_EMAIL}" -F "password=${GC_ENC_PW}" \
    -F "deviceId=${GC_FP}" -F "singleId=${GC_FP}")

GC_TOKEN=$(echo "$GC_LOGIN" | jq -r '.info // empty')
GC_CODE=$(echo "$GC_LOGIN" | jq -r '.code // empty')

if [ "$GC_CODE" != "0" ] || [ -z "$GC_TOKEN" ] || [ "$GC_TOKEN" = "null" ]; then
    echo "  [WARN] GoodCloud login failed - skipping registration."
    echo "  $(echo "$GC_LOGIN" | jq -r '.msg // empty')"
    rm -f "$GC_RSA_PEM"
    exit 0
fi
echo "  [OK] Authenticated"

# Check if device already exists in org
echo "  Checking if device already registered..."
GC_SEARCH=$(gc_api_call "POST" "/cloud-api/cloud/v2/orgDevice/advancedSearch" "$GC_TOKEN" \
    "{\"orgId\":\"${GC_ORG_ID}\",\"pageNum\":1,\"pageSize\":500}")

GC_MATCH=$(echo "$GC_SEARCH" | jq -e --arg mac "$GC_MAC" --arg ddns "$DEVICE_ID" --arg sn "$DEVICE_SN" \
    '.info.records[] | select(.mac == $mac or .ddns == $ddns or .sn == $sn)' 2>/dev/null)

if [ -n "$GC_MATCH" ] && [ "$GC_MATCH" != "null" ]; then
    GC_DEVICE_NAME=$(echo "$GC_MATCH" | jq -r '.deviceName // "N/A"' | head -1)
    GC_STATUS_CODE=$(echo "$GC_MATCH" | jq -r '.status // "N/A"' | head -1)
    case "$GC_STATUS_CODE" in
        1) GC_CLOUD_STATUS="Online" ;;
        0) GC_CLOUD_STATUS="Offline" ;;
        *) GC_CLOUD_STATUS="$GC_STATUS_CODE" ;;
    esac
    echo "  [OK] Device already registered as: $GC_DEVICE_NAME ($GC_CLOUD_STATUS)"
else
    # Add device to org
    echo "  Device not found in org. Adding..."

    # Prompt for device name
    read -rp "  Enter device name for GoodCloud: " GC_NEW_NAME
    if [ -z "$GC_NEW_NAME" ]; then
        GC_NEW_NAME="$HOSTNAME"
        echo "  Using hostname: $GC_NEW_NAME"
    fi

    GC_ADD=$(gc_api_call "POST" "/cloud-api/cloud/v2/orgDevice" "$GC_TOKEN" \
        "{\"ddns\":\"${DEVICE_ID}\",\"mac\":\"${GC_MAC}\",\"sn\":\"${DEVICE_SN}\",\"orgId\":\"${GC_ORG_ID}\",\"deviceName\":\"${GC_NEW_NAME}\"}")

    GC_ADD_CODE=$(echo "$GC_ADD" | jq -r '.code // empty')
    if [ "$GC_ADD_CODE" = "0" ]; then
        echo "  [OK] Device added to GoodCloud as: $GC_NEW_NAME"
        GC_DEVICE_NAME="$GC_NEW_NAME"
        GC_CLOUD_STATUS="Newly Added"
    else
        GC_ADD_MSG=$(echo "$GC_ADD" | jq -r '.msg // empty')
        echo "  [WARN] Could not add device: $GC_ADD_MSG"
        GC_DEVICE_NAME="ADD FAILED"
        GC_CLOUD_STATUS="$GC_ADD_MSG"
    fi
fi

rm -f "$GC_RSA_PEM"

# ---- Write CSV row ----
echo "\"$CSV_TIMESTAMP\",\"${DEVICE_MAC:-N/A}\",\"${DEVICE_SN:-N/A}\",\"${DEVICE_ID:-N/A}\",\"${DEVICE_IMEI:-N/A}\",\"${DEVICE_ICCID:-N/A}\",\"${HOSTNAME:-N/A}\",\"${DEVICE_MODEL:-N/A}\",\"$R_CONNECTIVITY\",\"$R_LAN_IP\",\"$R_DHCP_START\",\"$R_DHCP_LIMIT\",\"$R_INTERNET_GOOGLE\",\"$R_INTERNET_CLOUDFLARE\",\"$R_GOODCLOUD\",\"$R_WIFI_2G\",\"$R_WIFI_5G\",\"$R_RTTY_SSH\",\"$R_RTTY_WEB\",\"$R_RESET_SOFT\",\"$R_RESET_HARD\",\"$R_LED_SOFT_ON\",\"$R_LED_SOFT_OFF\",\"$R_LED_HARD_ON\",\"$R_LED_HARD_OFF\",$PASS,$FAIL,$TOTAL,\"$OVERALL_STATUS\",\"$GC_DEVICE_NAME\",\"$GC_CLOUD_STATUS\"" >> "$CSV_LOG"

echo ""
echo "  [OK] Results logged to $CSV_LOG"

# Write status for desktop launcher
echo "RESULT=PASS" > "$STATUS_FILE"
echo "PASS_COUNT=$PASS" >> "$STATUS_FILE"
echo "FAIL_COUNT=$FAIL" >> "$STATUS_FILE"
echo "TOTAL=$TOTAL" >> "$STATUS_FILE"
echo "MAC=${DEVICE_MAC:-N/A}" >> "$STATUS_FILE"
echo "SN=${DEVICE_SN:-N/A}" >> "$STATUS_FILE"
echo "GC_NAME=$GC_DEVICE_NAME" >> "$STATUS_FILE"
echo "GC_STATUS=$GC_CLOUD_STATUS" >> "$STATUS_FILE"

echo ""
echo "=========================================="
echo "Done."
echo "=========================================="
