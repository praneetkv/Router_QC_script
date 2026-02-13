#!/bin/bash

##############################################
# Installs Router QC desktop shortcut
# Run once after extracting the zip
##############################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Make scripts executable
chmod +x "${SCRIPT_DIR}/verify_all_settings.sh"
chmod +x "${SCRIPT_DIR}/verify_router_gui.sh"

# Create desktop shortcut with correct path
DESKTOP_FILE="$HOME/Desktop/Verify_Router.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Verify Router
Comment=Verify GL.iNet router settings and register on GoodCloud
Exec=gnome-terminal -- bash ${SCRIPT_DIR}/verify_router_gui.sh
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;
EOF

chmod +x "$DESKTOP_FILE"

echo "Installed! Desktop shortcut created at: $DESKTOP_FILE"
echo "Right-click the icon on the desktop and select 'Allow Launching'."
