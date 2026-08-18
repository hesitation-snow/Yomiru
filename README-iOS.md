# Yomiru iOS 构建说明

> iOS 正式包只能在 macOS + Xcode 环境中编译和签名。Windows 无法直接生成可安装的 IPA。

## 工程信息

- Bundle ID：`com.yutro.yomiru`
- 应用名称：`Yomiru`
- 平台工程：`ios/`

## 本地构建

```bash
flutter pub get
flutter build ios --release --no-codesign
```

需要发布或安装到真机时，请在 Xcode 中打开 `ios/Runner.xcworkspace`，配置自己的 Apple Developer Team、签名证书和 provisioning profile，再执行 Archive 或导出 IPA。

## GitHub Actions

仓库当前不通过 GitHub Actions 自动生成 IPA 或 APK。现有工作流仅保留为手动审核后的备用配置，推送代码不会触发构建。

## 发布前检查

- 确认 Apple Developer 后台已注册 `com.yutro.yomiru`。
- 使用自己的签名配置，不要把证书、私钥或 provisioning profile 提交到仓库。
- 发布前确认接口地址、应用名称和隐私说明与实际版本一致。
- 不要在来源不明的 IPA 中输入账号密码。
