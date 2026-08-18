# Yomiru

一个面向个人学习与兼容性研究的 Flutter 轻小说第三方客户端。

> **非官方声明**：Yomiru 与 `lightnovel.fun` 及其运营方没有隶属、授权或合作关系。项目不提供任何绕过访问控制、签名校验、付费机制或站点限制的功能。

## 项目概览

Yomiru 提供以下基础能力：

- 首页推荐、频道、榜单与搜索
- 书籍详情、卷章浏览和阅读器
- 服务器书架与阅读历史同步
- 书评、段评、动态、消息和私信
- 登录、头像、个人资料与关注

当前公开版本仅保留正式功能，不包含开发测试入口。

## 技术栈

- Flutter / Dart
- Android：Kotlin、Android SDK
- iOS：Xcode、CocoaPods
- 会话安全存储：Android Keystore / iOS Keychain（通过 `flutter_secure_storage`）

当前应用标识：

- Android application ID：`com.yutro.yomiru`
- iOS Bundle ID：`com.yutro.yomiru`
- 应用名称：`Yomiru`

## 本地运行

```bash
flutter pub get
flutter run
```

要求 Flutter 3.x、Dart 3、Android SDK 34+；iOS 正式构建需要 macOS 与 Xcode。

Android 正式构建必须配置仓库外的 `android/key.properties` 和 release keystore。密钥文件已加入 `.gitignore`，缺少签名配置时构建会明确失败，不会静默使用 Debug 签名。

## 安全与隐私

- 登录返回的 `security_key` 是会话凭据，只保存到系统安全存储，不再写入 `SharedPreferences`。
- 用户名和密码只用于登录请求，不会写入本地持久化存储。
- 仓库不应包含 token、cookie、代理密钥、测试账号或服务端 secret；提交前请检查配置和构建日志。
- 客户端访问站点接口和部分公开页面时使用 HTTPS。请求中的 Origin、Referer、User-Agent 仅用于兼容站点请求，不代表获得额外权限。
- 签到、任务、章节解锁、评论、关注和私信等操作可能改变账号状态或消耗站内权益，请由用户主动操作并遵守站点规则。
- 只使用自己的账号，不要分享密码、`security_key` 或应用数据。怀疑凭据泄露时，应立即在站点侧修改密码并使会话失效。

## 构建与发布约定

- 当前仓库不通过 GitHub Actions 自动生成 APK 或 IPA；现有工作流仅保留为手动审核后的备用配置。
- 正式 Android 包应使用项目维护者控制的 release keystore，并在发布时提供校验值。
- iOS 正式包必须在 macOS/Xcode 中完成签名；请在 Apple Developer 后台注册 `com.yutro.yomiru`。
- 项目代码以 MIT License 发布，详见 [LICENSE](LICENSE)；站点内容、封面、字体、图标和第三方依赖仍受各自权利与服务条款约束。

## 项目结构

```text
lib/
├── api/       # HTTP 客户端、接口封装、模型与安全会话存储
├── pages/     # 首页、搜索、阅读器、动态、消息和设置页面
└── widgets/   # 通用卡片、封面和错误提示组件
android/       # Android 平台工程
ios/           # iOS 平台工程
```

## 免责声明

本项目仅用于个人学习、兼容性研究和自用。站点接口、内容和规则可能随时变化，项目不保证持续可用。用户应自行承担账号操作、内容访问和第三方服务使用产生的责任；如收到权利人或服务方的合规要求，应及时停止相关功能并配合处理。
