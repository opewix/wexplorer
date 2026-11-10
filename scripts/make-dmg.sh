#!/bin/zsh
# Собирает установочный образ build/wexplorer-<версия>.dmg: приложение + ярлык «Программы».
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-0.4}"
./scripts/bundle.sh

STAGE=build/dmg
DMG="build/wexplorer-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/WExplorer.app" "$STAGE/"
ln -s /Applications "$STAGE/Программы"

hdiutil create -volname "WExplorer $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Установщик: $DMG"
