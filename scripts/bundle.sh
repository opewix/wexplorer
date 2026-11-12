#!/bin/zsh
# Собирает «WExplorer.app» в build/ (без Xcode, только SwiftPM).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/WExplorer.app"
VERSION="${VERSION:-0.11}"
rm -rf "$APP"
# Языки интерфейса берём из Sources/WExplorer/Localization/Languages/*.swift (code: "xx").
LANGS=($(grep -ho 'code: "[a-zA-Z-]*"' Sources/WExplorer/Localization/Languages/*.swift | cut -d'"' -f2))
mkdir -p "$APP/Contents/MacOS"
LOCALIZATIONS=""
for lang in $LANGS; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
  LOCALIZATIONS="$LOCALIZATIONS<string>$lang</string>"
done
cp .build/release/WExplorer "$APP/Contents/MacOS/WExplorer"

# Иконка приложения: рисуем из нашего набора и собираем .icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc -O -o build/appicon scripts/appicon/main.swift
build/appicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WExplorer</string>
<key>CFBundleDisplayName</key><string>WExplorer</string>
<key>CFBundleIdentifier</key><string>dev.oleg.wexplorer</string>
<key>CFBundleExecutable</key><string>WExplorer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array>$LOCALIZATIONS</array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>WExplorer показывает содержимое папки «Рабочий стол».</string>
<key>NSDocumentsFolderUsageDescription</key><string>WExplorer показывает содержимое папки «Документы».</string>
<key>NSDownloadsFolderUsageDescription</key><string>WExplorer показывает содержимое папки «Загрузки».</string>
<key>NSRemovableVolumesUsageDescription</key><string>WExplorer показывает содержимое съёмных дисков.</string>
<key>NSNetworkVolumesUsageDescription</key><string>WExplorer показывает содержимое сетевых дисков.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Готово: $APP"
