#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
DERIVED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sonar-mac-derived.XXXXXX")"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sonar-mac-stage.XXXXXX")"

cleanup() {
  rm -rf "${DERIVED_DIR}" "${STAGE_DIR}"
}
trap cleanup EXIT

echo "==> 正在编译 SonarMac (Release)..."
xcodebuild -project "${PROJECT_ROOT}/Sonar.xcodeproj" \
  -scheme SonarMac \
  -configuration Release \
  -derivedDataPath "${DERIVED_DIR}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build

APP_PATH="${DERIVED_DIR}/Build/Products/Release/SonarMac.app"

if [ ! -d "${APP_PATH}" ]; then
  echo "错误: 未找到构建产物 ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"

echo "==> 正在打包 SonarMac.zip..."
(cd "${DERIVED_DIR}/Build/Products/Release" && zip -qry "${BUILD_DIR}/SonarMac.zip" "SonarMac.app")
shasum -a 256 "${BUILD_DIR}/SonarMac.zip" > "${BUILD_DIR}/SonarMac.zip.sha256"

echo "==> 正在生成自定义安装界面背景图..."
BG_DIR="${STAGE_DIR}/.background"
mkdir -p "${BG_DIR}"
MODULE_CACHE="${TMPDIR:-/tmp}/swift-modules"
mkdir -p "${MODULE_CACHE}"
swift -module-cache-path "${MODULE_CACHE}" "${PROJECT_ROOT}/scripts/generate-dmg-background.swift" "${BG_DIR}/background.png"

echo "==> 正在准备 DMG 安装包内容..."
cp -R "${APP_PATH}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

echo "==> 正在配置 DMG 拖拽安装交互界面..."
DMG_PATH="${BUILD_DIR}/SonarMac.dmg"
TEMP_DMG="${DERIVED_DIR}/Sonar_rw.dmg"
rm -f "${DMG_PATH}" "${DMG_PATH}.sha256" "${TEMP_DMG}"

# 创建可读写临时镜像以写入 Finder 视图配置 (.DS_Store)
hdiutil create -srcfolder "${STAGE_DIR}" -volname "Sonar" -fs HFS+ -format UDRW -ov "${TEMP_DMG}" >/dev/null

# 确保无残留挂载
hdiutil detach "/Volumes/Sonar" 2>/dev/null || true

ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}")
DEV=$(echo "${ATTACH_OUT}" | grep '/Volumes/Sonar' | awk '{print $1}')

if osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Sonar"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 1060, 600}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "SonarMac.app" of container window to {175, 195}
        set position of item "Applications" of container window to {485, 195}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
then
    echo "==> Finder 拖拽安装界面配置成功"
else
    echo "==> 提示: 未能配置 Finder 窗口视图（可能处于无 GUI 环境），保留默认布局"
fi

sync
hdiutil detach "${DEV}" 2>/dev/null || hdiutil detach "/Volumes/Sonar" 2>/dev/null || true

echo "==> 正在生成最终压缩版 SonarMac.dmg..."
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -ov -o "${DMG_PATH}" >/dev/null
rm -f "${TEMP_DMG}"
shasum -a 256 "${DMG_PATH}" > "${DMG_PATH}.sha256"

echo ""
echo "=================================================="
echo " 恭喜！macOS 打包已顺利完成："
echo " DMG 安装包: ${DMG_PATH}"
echo " ZIP 压缩包: ${BUILD_DIR}/SonarMac.zip"
echo "=================================================="
echo "普通 Mac 用户首次运行若遇到安全提示，可在终端执行："
echo "  xattr -cr /Applications/SonarMac.app"
echo "=================================================="
