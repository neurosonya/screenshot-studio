#!/bin/bash
# Собирает Скриншот-студию в настоящее Mac-приложение и DMG.
# Запуск: bash app/build.sh   (из папки "Красивые скриншоты")
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Скриншот-студия"
DIST="../dist"
APP="$DIST/$APP_NAME.app"
BUILD="build"

echo "==> Чищу старую сборку"
rm -rf "$DIST" "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

echo "==> Рисую иконку"
swiftc -O Sources/MakeIcon.swift -o "$BUILD/makeicon"
"$BUILD/makeicon" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Компилирую приложение"
swiftc -O -framework Cocoa -framework WebKit -framework Carbon \
    Sources/main.swift Sources/Bridge.swift \
    -o "$APP/Contents/MacOS/ScreenshotStudio"

echo "==> Собираю бандл"
cp Info.plist "$APP/Contents/Info.plist"
cp "../index.html" "$APP/Contents/Resources/editor.html"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Подписываю (ad-hoc)"
codesign --force --deep --sign - "$APP"
# Когда появится аккаунт Apple Developer - заменить строку выше на:
#   codesign --force --deep --options runtime --sign "Developer ID Application: ИМЯ (TEAMID)" "$APP"
# и после сборки DMG выполнить нотаризацию:
#   xcrun notarytool submit "$DIST/$APP_NAME.dmg" --keychain-profile "notary" --wait
#   xcrun stapler staple "$DIST/$APP_NAME.dmg"

echo "==> Делаю DMG"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DIST/$APP_NAME.dmg"

echo
echo "Готово:"
echo "  $APP"
echo "  $DIST/$APP_NAME.dmg"
