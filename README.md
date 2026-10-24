# MyXLF

基于 Flutter 的成绩查询与分析客户端。

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

[`.github/workflows/release.yml`](.github/workflows/release.yml) 负责构建并发布 Android 安装包。

### 打标签发布

1. 更新 `pubspec.yaml` 中的 `version`（如 `1.2.3+4`）。
2. 提交并推送代码。
3. 创建并推送版本标签：

   ```bash
   git tag v1.2.3
   git push origin v1.2.3
   ```

工作流会：

1. 运行静态分析和单元测试。
2. 构建 Release APK 和 AAB。
3. 创建 GitHub Release（版本名取自标签去掉开头的 `v`），并附加以下文件：
   - `MyXLF-<version>.apk`：可直接安装的通用 APK
   - `MyXLF-<version>.aab`：用于 Google Play 上架
   - `SHA256SUMS-<version>.txt`：校验文件

也可以进入 **Actions → Release → Run workflow** 手动触发；版本号留空时使用 `pubspec.yaml` 中的版本。

### Android 签名（推荐）

未配置签名时，Release 会回退到 debug 签名，仅适合内部测试。正式发布请在仓库 **Settings → Secrets and variables → Actions** 中添加：

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 Base64 编码 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

生成 Base64：

```bash
base64 -w0 upload-keystore.jks > keystore.b64
```

本地构建已签名 Release 时，将 [`android/key.properties.example`](android/key.properties.example) 复制为 `android/key.properties` 并填写。该文件已被 `.gitignore` 忽略。
