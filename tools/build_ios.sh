#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode=check
case "${1:-}" in
    "") ;;
    --open|--install) mode="$1" ;;
    --help|-h)
        printf '用法：%s [--open | --install]\n' "$0"
        exit 0
        ;;
    *)
        printf '用法：%s [--open | --install]\n' "$0" >&2
        exit 2
        ;;
esac
if (( $# > 1 )); then
    printf '用法：%s [--open | --install]\n' "$0" >&2
    exit 2
fi

output="$PWD/build/ios"
scheme=zombie_siege
project="$output/$scheme.xcodeproj"
signed_data="$output/DerivedData/signed"
destination="generic/platform=iOS"
provisioning=(-allowProvisioningUpdates)

if [[ "$mode" == --install ]]; then
    device="${IOS_DEVICE_ID:-00008150-001C49940245401C}"
    if ! xcrun devicectl device info lockState --device "$device" --timeout 15; then
        printf '请连接并解锁 iPhone，在手机上信任此 Mac 后重试。\n' >&2
        exit 1
    fi
    destination="platform=iOS,id=$device"
    provisioning+=(-allowProvisioningDeviceRegistration)
fi

mkdir -p "$output"
touch "$output/.gdignore"
godot --headless --path . --import
godot --headless --path . -- --fontcheck="$PWD/tools/font_chars.txt"
godot --headless --path . --export-debug "iOS" "$project"

# Godot 模板会写入空的权限说明，Xcode 会为这些占位项发出警告。
info_plist="$output/$scheme/$scheme-Info.plist"
for key in NSCameraUsageDescription NSMicrophoneUsageDescription NSPhotoLibraryUsageDescription; do
    if value="$(plutil -extract "$key" raw -o - "$info_plist" 2>/dev/null)" && [[ -z "$value" ]]; then
        plutil -remove "$key" "$info_plist"
    fi
done

if [[ "$mode" == --open ]]; then
    open -a Xcode "$project"
    exit 0
fi

xcode_args=(-project "$project" -scheme "$scheme" -sdk iphoneos -configuration Debug)
if [[ "$mode" == check ]]; then
    xcodebuild "${xcode_args[@]}" -destination "$destination" \
        -derivedDataPath "$output/DerivedData/unsigned" CODE_SIGNING_ALLOWED=NO build
fi

if xcodebuild "${xcode_args[@]}" -destination "$destination" \
    -derivedDataPath "$signed_data" "${provisioning[@]}" build; then
    printf '已通过 iOS Debug 签名构建。\n'
else
    build_result=$?
    printf 'iOS 签名构建失败（退出码 %s）。请查看上方 Xcode 错误。\n' "$build_result" >&2
    exit "$build_result"
fi

if [[ "$mode" == --install ]]; then
    app="$signed_data/Build/Products/Debug-iphoneos/$scheme.app"
    bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app/Info.plist")"
    xcrun devicectl device install app --device "$device" "$app"
    xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle_id"
fi
