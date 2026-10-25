# MyXLF

基于 Flutter 的成绩查询与分析客户端。

## 安装

从 [GitHub Releases](https://github.com/xuanxuan1231/MyXLF/releases/latest) 下载，或者通过 [蓝奏云 (密码 5cfc)](https://wwasj.lanzouu.com/b01i5y6dji) 下载。

## 本地开发

项目使用 [FVM](https://fvm.app/) 固定 Flutter 版本（见 `.fvmrc`）：

```bash
fvm install
fvm flutter pub get
fvm flutter run
```

常用命令：

```bash
fvm flutter analyze
fvm flutter test --exclude-tags e2e   # 单元测试（跳过需要真实服务器的 e2e）
fvm flutter test test/e2e_test.dart   # 手动运行端到端测试
```

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) 在推送到 `main`、向 `main` 提交 PR 或手动触发时运行：

- `flutter analyze`
- `flutter test --exclude-tags e2e`

## 发布 Release

[`.github/workflows/release.yml`](.github/workflows/release.yml) 负责构建并发布 Android / iOS 安装包。

### 打标签发布

1. 更新 `pubspec.yaml` 中的 `version`（如 `1.2.3+4`）。
2. 提交并推送代码。
3. 创建并推送版本标签：

   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

工作流会：

1. 运行静态分析和单元测试（Android 任务）。
2. 构建 Release APK、AAB 和 IPA。
3. 创建 GitHub Release（版本名取自标签去掉开头的 `v`），Release Notes 由 [git-cliff](https://git-cliff.org/) 根据提交历史生成，并附加以下文件：
   - `MyXLF-<version>.apk`：可直接安装的通用 APK
   - `MyXLF-<version>.aab`：用于 Google Play 上架
   - `MyXLF-<version>.ipa`：已签名的 iOS 安装包（配置 iOS 签名时）
   - `MyXLF-<version>-unsigned.ipa`：未签名 IPA（未配置 iOS 签名时），用户需自行重签侧载
   - `SHA256SUMS-<version>-android.txt` / `SHA256SUMS-<version>-ios.txt`：校验文件

也可以进入 **Actions → Release → Run workflow** 手动触发；版本号留空时使用 `pubspec.yaml` 中的版本。

### Release Notes

Release Notes 由 git-cliff 根据上一个版本标签到本次标签之间的提交生成，规则见 [`cliff.toml`](cliff.toml)：

- 提交信息建议遵循 [Conventional Commits](https://www.conventionalcommits.org/)，如 `feat: 新增成绩对比`、`fix: 修复登录失败`。
- `feat` / `fix` / `perf` / `refactor` / `docs` / `revert` 会分组展示，其余提交归入「其他改动」。
- 本地预览：

  ```bash
  git cliff --latest                  # 最新版本的 Release Notes
  git cliff --unreleased --tag v1.2.3 # 模拟下一个版本的 Release Notes
  ```

### iOS 侧载

没有 Apple Developer Program 也可以发布 IPA：工作流会构建未签名的 `MyXLF-<version>-unsigned.ipa`。它不能直接安装，用户需要用 AltStore、SideStore、Sideloadly 或 Xcode 以自己的 Apple ID 重新签名后安装（免费 Apple ID 签名 7 天后过期）。

已签名 IPA 需要配置 Apple Distribution 证书和描述文件；详细步骤、侧载方法和常见问题见 **[docs/signing.md](docs/signing.md)**。

### 签名配置

详细步骤见 **[docs/signing.md](docs/signing.md)**，包括：

- 创建 Android keystore 并配置为 GitHub Secrets
- 创建 Apple Distribution 证书（`.p12`）和描述文件（`.mobileprovision`）
- 将证书 / 描述文件转为 Base64 并配置 iOS Secrets

未配置 Android 签名时会回退到 debug 签名；未配置 iOS 签名时会构建未签名 IPA（供侧载），不影响 Android 发布。iOS 构建运行在 `macos-latest`。

常用 Secrets：

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Android keystore 的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Android keystore 密码 |
| `ANDROID_KEY_ALIAS` | Android 密钥别名 |
| `ANDROID_KEY_PASSWORD` | Android 密钥密码 |
| `IOS_CERTIFICATE_BASE64` | iOS `.p12` 的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | iOS `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | iOS 描述文件的 Base64 |
| `IOS_PROVISIONING_PROFILE_SPECIFIER` | 描述文件的 Name |
| `IOS_TEAM_ID` | Apple Developer Team ID |

本地构建已签名 Android Release 时，将 [`android/key.properties.example`](android/key.properties.example) 复制为 `android/key.properties` 并填写。该文件已被 `.gitignore` 忽略。
