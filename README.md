# GL.iNet Router QC Verification

Automated quality control verification for GL.iNet X2000 routers. Checks all critical settings, retrieves device info (IMEI/ICCID), registers the device on GoodCloud under the virtusense organization, and logs results to a CSV.

## Files

| File | Description |
|------|-------------|
| `verify_all_settings.sh` | Main script. Runs all 17 QC checks, retrieves IMEI/ICCID, registers device on GoodCloud, and logs results to CSV. |
| `verify_router_gui.sh` | Desktop wrapper. Runs `verify_all_settings.sh` in a terminal and shows a GUI popup with the result. |
| `install.sh` | Run once after extracting. Makes scripts executable and creates a desktop shortcut. |
| `Verify_Router.desktop` | Template desktop shortcut (used by `install.sh`). |
| `router_qc_log.csv` | Auto-generated CSV log (created next to the scripts). Each row is one QC run with all test results and device info. |

## Dependencies

Install on the NUC (Ubuntu):

```bash
sudo apt install jq sshpass openssh-client curl openssl
```

| Package | Required | Purpose |
|---------|----------|---------|
| `jq` | Yes | Parse GoodCloud API JSON responses |
| `curl` | Yes | GoodCloud API HTTP requests |
| `openssl` | Yes | RSA encryption for GoodCloud authentication |
| `ssh` (openssh-client) | Yes | SSH into router to read settings and device info |
| `sshpass` | Optional | Allows password-based SSH without key setup. If not installed, the script will set up SSH key auth on first run (prompts for router password once). |
| `zenity` | Optional | GUI popups for desktop launcher. Pre-installed on Ubuntu GNOME. |

## Setup

1. Connect the NUC to the router's LAN port (router IP: `172.16.1.1`).

2. Extract the zip to any folder (e.g. `~/Documents/Router_QC/`).

3. Run the installer:
   ```bash
   cd ~/Documents/Router_QC/
   chmod +x install.sh
   ./install.sh
   ```
   This makes scripts executable and creates a desktop shortcut.

4. Right-click the **Verify Router** icon on the desktop and select **Allow Launching**.

## Usage

### Desktop (click to run)
Double-click **Verify Router** on the desktop. A terminal opens showing progress, then a popup appears:
- **Red popup** - QC failed. Shows pass/fail count. Fix issues and re-run.
- **Yellow popup** - QC passed but device already registered on GoodCloud. Shows device name and online status.
- **Green popup** - QC passed and device newly added to GoodCloud.

### Terminal
```bash
./verify_all_settings.sh
```

## What It Checks

| # | Check | Expected |
|---|-------|----------|
| 1 | Router connectivity | Reachable at 172.16.1.1 |
| 2 | LAN IP | 172.16.1.1 |
| 3 | DHCP start | 100 |
| 4 | DHCP limit | 150 |
| 5 | Internet (Google DNS) | 8.8.8.8 reachable |
| 6 | Internet (Cloudflare) | 1.1.1.1 reachable |
| 7 | GoodCloud enabled | 1 |
| 8 | WiFi 2.4GHz disabled | 1 |
| 9 | WiFi 5GHz disabled | 1 |
| 10 | RTTY SSH enabled | 1 |
| 11 | RTTY Web enabled | 1 |
| 12 | Soft reset time | 10s |
| 13 | Hard reset time | 120s |
| 14 | LED soft blink ON | 250ms |
| 15 | LED soft blink OFF | 250ms |
| 16 | LED hard blink ON | 125ms |
| 17 | LED hard blink OFF | 125ms |

## Device Info Collected

- Hostname, Model, Device ID (DDNS), Serial Number, MAC Address
- IMEI (from modem via AT+CGSN)
- ICCID (from SIM via AT+QCCID)

## CSV Output

Results are appended to `router_qc_log.csv` (in the same folder as the scripts). Columns:

```
Timestamp, MAC_Address, Serial_Number, Device_ID, IMEI, ICCID, Hostname, Model,
[17 test results: PASS/FAIL each],
Passed, Failed, Total, Overall_Status, GoodCloud_Name, GoodCloud_Online
```

## Credentials

Hardcoded in the scripts (change if needed):

| Credential | Value | Used For |
|-----------|-------|----------|
| Router IP | 172.16.1.1 | SSH into router |
| Router password | MusterLegoWaking | SSH key setup / sshpass |
| GoodCloud email | praneetk@virtusense.com | GoodCloud API login |
| GoodCloud password | VstPraneet | GoodCloud API login |
| GoodCloud org ID | d6268cca351035d902c9301bbfd8ed12 | virtusense organization |

## Troubleshooting

**Router not reachable**: Ensure NUC is connected to router LAN port and has IP in 172.16.1.x range.

**SSH fails**: The script auto-sets up SSH keys on first run. If it fails, manually run:
```bash
ssh-copy-id -o HostKeyAlgorithms=+ssh-rsa root@172.16.1.1
```

**GoodCloud login fails**: Check credentials. Account may be temporarily locked after too many attempts (wait 5 min).

**IMEI/ICCID shows N/A**: SIM may not be inserted or modem not detected. Check modem bus with:
```bash
ssh root@172.16.1.1 "cat /proc/gl-hw-info/build-in-modem"
```

**Desktop icon won't launch**: Right-click > Properties > Permissions > check "Allow executing file as program". Or right-click > Allow Launching.
