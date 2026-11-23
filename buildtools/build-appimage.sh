#!/usr/bin/env bash
set -euo pipefail

APP_DIR="server_manager.AppDir"
APPIMAGE_TOOL="buildtools/appimagetool-x86_64.AppImage"
APP_VERSION=$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
APPIMAGE_NAME="server_manager_${APP_VERSION}.AppImage"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp -r build/linux/x64/release/bundle/* "$APP_DIR"
cp -r buildtools/appimage_config/* "$APP_DIR"
cp assets/icons/icon-padded.png "$APP_DIR"
chmod +x "$APPIMAGE_TOOL"
chmod +x "$APP_DIR/AppRun"
"$APPIMAGE_TOOL" "$APP_DIR" "$APPIMAGE_NAME"
