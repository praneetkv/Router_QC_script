#!/bin/bash

##############################################
# Desktop wrapper for verify_all_settings.sh
# Runs verification in terminal, then shows
# GUI popup with the result
##############################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/verify_all_settings.sh"
STATUS_FILE="/tmp/verify_router_status"

# Run the verification script (visible in terminal)
"$SCRIPT"
EXIT_CODE=$?

# Read status file
if [ -f "$STATUS_FILE" ]; then
    source "$STATUS_FILE"
else
    zenity --error --title="Router Verification" \
        --text="Could not read verification results.\nThe router may not be reachable." \
        --width=350 2>/dev/null
    echo ""
    echo "Press Enter to close..."
    read
    exit 1
fi

# Show appropriate popup
if [ "$RESULT" = "PASS" ]; then
    if [ "$GC_STATUS" = "Online" ] || [ "$GC_STATUS" = "Offline" ]; then
        # Device already exists in GoodCloud
        zenity --warning --title="Router Verification - Already Registered" \
            --text="All $TOTAL checks PASSED\n\nDevice already on GoodCloud:\n  Name: $GC_NAME\n  Status: $GC_STATUS\n  MAC: $MAC\n  SN: $SN" \
            --width=400 2>/dev/null
    else
        # Newly added or other success
        zenity --info --title="Router Verification - Success" \
            --text="All $TOTAL checks PASSED\n\nGoodCloud: $GC_NAME ($GC_STATUS)\nMAC: $MAC\nSN: $SN" \
            --width=400 2>/dev/null
    fi
else
    # Checks failed
    zenity --error --title="Router Verification - UNSUCCESSFUL" \
        --text="VERIFICATION FAILED\n\nPassed: $PASS_COUNT / $TOTAL\nFailed: $FAIL_COUNT / $TOTAL\n\nMAC: $MAC\nSN: $SN\n\nFix failures before GoodCloud registration.\nCheck terminal output for details." \
        --width=400 2>/dev/null
fi

echo ""
echo "Press Enter to close..."
read
