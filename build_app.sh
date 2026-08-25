#!/bin/zsh
# 把 trackpad_pro 打包成 .app，这样它在「辅助功能」列表里有自己的身份。
# 用法:  ./build_app.sh              （ad-hoc 签名，每次重新编译后需在辅助功能里取消再勾选）
#        ./build_app.sh --install    （同时安装到 /Applications，Spotlight/启动台可搜到）
#        ./build_app.sh --universal  （arm64 + x86_64 通用二进制，分架构编译后 lipo 合并，
#                                      只需 Command Line Tools，不需要完整 Xcode）
#        ./build_app.sh --universal --zip （发布打包：生成 dist/trackpad_pro-vX.Y.Z.zip，
#                                      用 ditto 压缩以保留签名；不重置本机辅助功能授权）
#        CODESIGN_IDENTITY="My Cert" ./build_app.sh   （用自签证书签名，权限可跨版本保留）
set -e
cd "$(dirname "$0")"

VERSION="0.2.0"

INSTALL=0 UNIVERSAL=0 ZIP=0
for arg in "$@"; do
  case "$arg" in
    --install)   INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    --zip)       ZIP=1 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

if [[ $UNIVERSAL == 1 ]]; then
  # `swift build --arch a --arch b` 需要完整 Xcode 的 xcbuild；
  # 分架构编译 + lipo 只依赖 Command Line Tools。
  swift build -c release --triple arm64-apple-macosx
  swift build -c release --triple x86_64-apple-macosx
  mkdir -p .build/universal
  lipo -create \
    .build/arm64-apple-macosx/release/trackpad_pro \
    .build/x86_64-apple-macosx/release/trackpad_pro \
    -output .build/universal/trackpad_pro
  BIN=.build/universal/trackpad_pro
else
  swift build -c release
  BIN=.build/release/trackpad_pro
fi

APP=dist/trackpad_pro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>      <string>local.trackpad-pro</string>
    <key>CFBundleName</key>            <string>trackpad_pro</string>
    <key>CFBundleExecutable</key>      <string>trackpad_pro</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key> <string>© 2026 g03024735. MIT License.</string>
</dict>
</plist>
PLIST

cp "$BIN" "$APP/Contents/MacOS/trackpad_pro"
codesign --force --sign "${CODESIGN_IDENTITY:--}" --identifier local.trackpad-pro "$APP"

# ad-hoc 签名每次都变，旧的辅助功能授权会失效但开关仍显示已勾选。
# 本机开发迭代时清掉授权记录，下次启动会重新弹出授权提示。
# 发布打包（--zip）时跳过：不动打包机器上的授权状态。
if [[ -z "$CODESIGN_IDENTITY" && $ZIP == 0 ]]; then
  pkill -x trackpad_pro 2>/dev/null || true
  tccutil reset Accessibility local.trackpad-pro >/dev/null 2>&1 || true
  echo "已重置辅助功能授权（下次启动会显示权限引导面板）"
fi

# 安装到 /Applications：应用不在 Dock 显示，用户靠 Spotlight/启动台/访达启动，
# 装进标准位置才搜得到；开机自启注册的路径也不会因 dist 目录变动而失效。
if [[ $INSTALL == 1 ]]; then
  pkill -x trackpad_pro 2>/dev/null || true
  rm -rf /Applications/trackpad_pro.app
  cp -R "$APP" /Applications/
  APP=/Applications/trackpad_pro.app
  echo "已安装到 $APP"
fi

if [[ $ZIP == 1 ]]; then
  # ditto 保留扩展属性与签名结构，普通 zip 会破坏 .app 签名
  ZIPFILE=dist/trackpad_pro-v${VERSION}.zip
  rm -f "$ZIPFILE"
  ditto -c -k --keepParent "$APP" "$ZIPFILE"
  echo "发布包: $ZIPFILE ($(du -h "$ZIPFILE" | cut -f1 | tr -d ' '))"
  lipo -archs "$APP/Contents/MacOS/trackpad_pro" 2>/dev/null | sed 's/^/架构: /'
fi

echo
echo "已生成 $APP"
echo "启动:            open $APP"
echo "带调试日志启动:  open $APP --args --debug"
echo "查看日志:        tail -f ~/Library/Logs/trackpad_pro.log"
echo "退出:            pkill -x trackpad_pro"
