# Yomiru iOS 构建说明

> iOS 正式包只能在 macOS + Xcode 环境中编译和签名。Windows 无法直接生成可安装的 IPA。

## 工程信息

- Bundle ID：`moe.yutro.yomiru`
- 应用名称：`Yomiru`
- 平台工程：`ios/`

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

需要发布或安装到真机时，请在 Xcode 中打开 `ios/Runner.xcworkspace`，配置自己的 Apple Developer Team、签名证书和 provisioning profile，再执行 Archive 或导出 IPA。

## GitHub Actions

推送形如 `v1.0.3` 的版本标签后，GitHub Actions 会构建并创建 GitHub Release，包含 Android APK 和 iOS IPA。

- Android Release 必须使用仓库 Secrets 中配置的正式签名 keystore。
- iOS 工作流产出未签名 IPA；安装到真机前仍需在 macOS/Xcode 中使用自己的 Apple Developer 签名。

## 发布前检查

- 确认 Apple Developer 后台已注册 `moe.yutro.yomiru`。
- 使用自己的签名配置，不要把证书、私钥或 provisioning profile 提交到仓库。
- 发布前确认接口地址、应用名称和隐私说明与实际版本一致。
- 不要在来源不明的 IPA 中输入账号密码。
