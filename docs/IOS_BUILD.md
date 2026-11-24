# 《僵尸围城》iOS 构建与安装

需要 macOS、命令行可用的 Godot 4.7.2、同版本 iOS 导出模板，以及已初始化的完整 Xcode。本项目使用 Xcode 27.2 和 iOS 27.2 SDK 验证。生成的 App 支持 iOS 15.0 起的 iPhone 和 iPad，并支持左右两种横屏方向。 [Godot iOS 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)

## 构建与打开

在仓库根目录运行相应命令。

```sh
./tools/build_ios.sh
./tools/build_ios.sh --open
```

默认模式依次导入 Godot 资源、检查字体、导出 Xcode 工程、编译未签名和自动签名的 Debug App。若签名检查失败，脚本会返回 Xcode 的退出码，未签名产物仍在 `build/ios/DerivedData/unsigned/Build/Products/Debug-iphoneos/`。

`--open` 导出并在 Xcode 中打开 `build/ios/zombie_siege.xcodeproj`。每次导出都会重新生成工程。需要修改团队或包标识符时，请更新 `export_presets.cfg` 中的 iOS 预设。

## 安装到 iPhone 17

1. 用数据线连接并解锁 iPhone，按提示信任此 Mac。若手机尚未开启开发者模式，进入「设置 → 隐私与安全性 → 开发者模式」开启，重启后按屏幕提示确认。 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
2. 在 Xcode 的「设置 → Apple 账户」登录拥有团队 `HPN8892DZ2` 权限的 Apple 账户。打开导出的工程，在 `zombie_siege` 目标的 **Signing & Capabilities** 中确认自动管理签名、团队和包标识符 `com.dora321.zombiesiege`，然后选中 iPhone 17。若 Xcode 提示注册设备，先完成注册以生成开发描述文件。 [Apple 真机签名说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
3. 在 Xcode 中点击运行，或在终端运行以下命令。脚本会为这台 iPhone 构建已签名的 Debug App，再通过 `devicectl` 安装并启动。使用其他设备时，通过 `IOS_DEVICE_ID` 环境变量指定该设备的 UDID。

   ```sh
   ./tools/build_ios.sh --install
   ```

4. 首次打开若提示「不受信任的开发者」，进入「设置 → 通用 → VPN 与设备管理」，选择对应的开发者并按屏幕提示信任，再打开游戏。

若 Xcode 显示 `No Accounts` 或 `No profiles`，先检查 Xcode 登录的账户，再确认该团队的开发描述文件包含目标设备。钥匙串里的开发证书需要配合开发描述文件才能安装到真机。 [Apple 开发描述文件说明](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)

## 更新图标与启动图

运行 `python3 tools/gen_ios_assets.py`，用 Python 标准库重新生成 `resources/ios/` 下的图标和启动图，再运行构建脚本。
