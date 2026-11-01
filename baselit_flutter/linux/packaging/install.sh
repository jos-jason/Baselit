#!/usr/bin/env bash
# Installs Baselit for the current user: the app goes in ~/.local/share/baselit,
# a `baselit` command in ~/.local/bin, and a launcher entry so it shows up in
# app menus (Walker on Omarchy). Run it from the unpacked download folder.
# Remove with: ./install.sh --uninstall
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app_dir="$HOME/.local/share/baselit"
bin_dir="$HOME/.local/bin"
desktop_file="$HOME/.local/share/applications/com.babymechanical.baselit.desktop"
icon_file="$HOME/.local/share/icons/hicolor/512x512/apps/com.babymechanical.baselit.png"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$app_dir" "$bin_dir/baselit" "$desktop_file" "$icon_file"
  echo "Baselit removed. Your inventory data in ~/.local/share/com.babymechanical.baselit was kept."
  exit 0
fi

rm -rf "$app_dir"
mkdir -p "$app_dir" "$bin_dir" "$(dirname "$desktop_file")" "$(dirname "$icon_file")"
cp -r "$here/baselit" "$here/lib" "$here/data" "$app_dir/"
cp "$here/baselit.png" "$icon_file"
ln -sf "$app_dir/baselit" "$bin_dir/baselit"

cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Baselit
Comment=Keep track of where your things are
Exec=$app_dir/baselit
Icon=com.babymechanical.baselit
Categories=Utility;
StartupWMClass=com.babymechanical.baselit
EOF

update-desktop-database "$(dirname "$desktop_file")" 2>/dev/null || true
echo "Baselit installed. Open it from your app launcher, or run: baselit"
