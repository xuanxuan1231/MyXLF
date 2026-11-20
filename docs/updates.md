# 应用内更新与 Cloudflare R2

MyXLF 所有平台都通过同一个 `manifest.json` 检查更新，不再调用 GitHub API。发布工作流会把各平台安装包和清单上传到 Cloudflare R2，Android 客户端可以直接在应用内下载、校验并调起系统安装程序。

> 已经安装的旧版本仍会通过 GitHub API 检查更新；用户升级到包含本功能的版本后，才会切换到 R2 清单。

## 发布后的文件结构

假设公开下载地址为 `https://myxlf.helloswx.top`：

```text
https://myxlf.helloswx.top/
├── manifest.json                         # 客户端读取的最新清单（每次发版覆盖）
└── releases/
    └── v1.2.3/
        └── <run_id>-<attempt>/
            ├── MyXLF-1.2.3.apk
            ├── MyXLF-1.2.3.aab          # 不上传，仅保留在 GitHub Release
            ├── MyXLF-1.2.3.ipa
            ├── MyXLF-1.2.3-windows-x64.zip
            ├── MyXLF-1.2.3-macos.zip
            ├── MyXLF-1.2.3-linux-x64.tar.gz
            └── manifest.json             # 该版本的清单快照
```

版本化目录以构建标识命名并使用长期缓存，`manifest.json` 使用 60 秒缓存；客户端请求时还会附加时间戳参数，避免 CDN 返回旧版本。

## 清单格式

```json
{
  "schema": 1,
  "app": "MyXLF",
  "channel": "stable",
  "prerelease": false,
  "version": "1.2.3",
  "build": 123,
  "released_at": "2026-11-20T12:00:00Z",
  "release_url": "https://github.com/xuanxuan1231/MyXLF/releases/tag/v1.2.3",
  "release_notes": "## 新功能\n- ...",
  "platforms": {
    "android": {
      "version": "1.2.3",
      "build": 123,
      "url": "https://myxlf.helloswx.top/releases/v1.2.3/<run_id>-<attempt>/MyXLF-1.2.3.apk",
      "size": 12345678,
      "sha256": "小写十六进制 SHA-256"
    },
    "windows": { "...": "..." },
    "macos": { "...": "..." },
    "linux": { "...": "..." },
    "ios": { "...": "..." }
  }
}
```

客户端规则：

- 只读取当前平台对应的 `platforms.<platform>`。清单里没有该平台时不提示更新（Web 版默认由浏览器刷新自动更新，因此通常不写 `web` 条目）。
- 先比较语义版本（`主.次.修订`），版本相同时再比较 `build`（Android 为 `versionCode`）。
- Android 有 `url` 且带 `sha256` 时走应用内下载安装；其他平台打开当前平台的 `url`，没有时退回 `release_url`。
- 下载完成后校验 `size` 与 `sha256`，通过后才交给系统安装程序。

清单由 [`scripts/publish_update_manifest.py`](../scripts/publish_update_manifest.py) 生成，大小和校验值直接读取发布产物，不需要手工维护。

## 已写入代码的公共配置

以下值不是机密，已经直接写在仓库里，不需要再配 Secret：

| 配置 | 值 | 位置 |
| --- | --- | --- |
| R2 S3 端点 | `https://66c00241227771096180f53b021844f0.r2.cloudflarestorage.com` | `release.yml` 顶部 |
| 存储桶 | `myxlf` | `release.yml` 顶部 |
| 公开下载域名 | `https://myxlf.helloswx.top` | `release.yml` 顶部 |
| 客户端清单地址 | `https://myxlf.helloswx.top/manifest.json` | `lib/config.dart` |
| 对象路径 | `releases/v<version>/<run_id>-<attempt>/` | workflow / 生成脚本 |
| 缓存策略 | 安装包长期缓存，根清单 60 秒 | workflow |

真正需要保密的只有 R2 的 **Access Key ID** 和 **Secret Access Key**。

## 配置 Cloudflare R2

### 1. 创建存储桶

在 Cloudflare 控制台进入 **R2 → Create bucket**，名称填 `myxlf`。如果使用其他名称，修改 `.github/workflows/release.yml` 顶部的 `R2_BUCKET`。

### 2. 开启公开访问

在 **R2 → 存储桶 → Settings → Custom Domains** 绑定 `myxlf.helloswx.top`。该域名目前已经可以访问；如果换域名，同时修改 workflow 顶部的 `R2_PUBLIC_BASE_URL` 和 `lib/config.dart` 的默认清单地址。也可以临时使用 R2 提供的 `r2.dev` 公开地址，但 `r2.dev` 有速率限制，不建议作为正式下载源。

### 3. 配置 Web 端 CORS（可选）

Android / iOS / 桌面客户端使用原生 HTTP，不需要 CORS。如果 Web 版也要检查更新，需要给存储桶配置 CORS，允许 Web 站点读取清单。仓库里已经提供可直接粘贴的 [`docs/r2-cors.json`](r2-cors.json)（公开只读资源，允许所有来源）：

```json
[
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }
]
```

### 4. 创建 R2 API 令牌

进入 **R2 → Manage R2 API Tokens → Create API token**：

- 权限：**Object Read & Write**
- 范围：只限 `myxlf` 这个桶
- 创建后保存 **Access Key ID** 和 **Secret Access Key**（Secret 只显示一次）

Account ID 已经包含在 workflow 的 S3 端点里，不需要单独配置。

### 5. 配置 GitHub Secrets

在仓库 **Settings → Secrets and variables → Actions → Secrets** 只需要添加两个：

| Secret | 说明 |
| --- | --- |
| `R2_ACCESS_KEY_ID` | R2 API 令牌的 Access Key ID |
| `R2_SECRET_ACCESS_KEY` | R2 API 令牌的 Secret Access Key |

也可以用 `gh`：

```bash
gh secret set R2_ACCESS_KEY_ID
gh secret set R2_SECRET_ACCESS_KEY
```

> 访问密钥只需要对象读写权限，不要使用拥有账户管理权限的 Global API Key。端点、桶名、公开域名都是公开信息，直接写在 workflow 里即可。

### 6. 配置客户端清单地址

客户端默认读取 `lib/config.dart` 中的：

```dart
const String kUpdateManifestUrl = String.fromEnvironment(
  'XLF_UPDATE_MANIFEST_URL',
  defaultValue: 'https://myxlf.helloswx.top/manifest.json',
);
```

Release 工作流会自动把 `R2_PUBLIC_BASE_URL` 拼成清单地址，并通过 `--dart-define` 注入所有平台构建，所以 CI 产物始终使用同一个地址。需要临时指向其他环境时，可以覆盖：

```bash
fvm flutter build apk --release \
  --dart-define=XLF_UPDATE_MANIFEST_URL=https://staging.example.com/manifest.json
```

`R2_PUBLIC_BASE_URL` 应指向存储桶根域名，不要带路径前缀；当前配置是 `https://myxlf.helloswx.top`。

## 发版流程

正常打标签或手动发版即可，工作流会在创建 GitHub Release 之前：

1. 下载所有平台产物到 `dist/`。
2. 用 git-cliff 生成 Release Notes。
3. 生成 `dist/manifest.json`。
4. 上传版本化产物到 `s3://myxlf/releases/v<version>/<run_id>-<attempt>/`。
5. 覆盖上传根目录 `manifest.json`（版本号带 `-` 的预发布版本只上传版本化快照，不覆盖稳定版清单）。
6. 创建 GitHub Release，并附带 `manifest.json`。

如果两个 R2 访问密钥都未配置，工作流会给出 warning 并跳过上传，GitHub Release 仍会创建；但客户端不会收到这次更新。只配置了其中一个时工作流会直接失败，避免发布半套配置。

手动触发时如果只构建部分平台，根清单也只包含这些平台，其他平台不会提示更新。正式发版建议构建全部平台，或至少包含 Android。

## 本地验证

生成一份清单（不需要连接 R2）：

```bash
mkdir -p dist
touch dist/MyXLF-1.2.3.apk
python3 scripts/publish_update_manifest.py \
  --dist dist \
  --version 1.2.3 \
  --build 123 \
  --base-url https://myxlf.helloswx.top \
  --release-url https://github.com/xuanxuan1231/MyXLF/releases/tag/v1.2.3 \
  --output dist/manifest.json
cat dist/manifest.json
```

检查线上清单：

```bash
curl -fsSL https://myxlf.helloswx.top/manifest.json | jq .
```

测试 Android 应用内更新时，当前安装包的 `versionName` / `versionCode` 必须小于清单中的值，并且新旧 APK 必须使用同一签名；否则系统会拒绝覆盖安装。

## Google Play 注意

应用内更新依赖 `REQUEST_INSTALL_PACKAGES` 权限，并会下载 APK 调用系统安装程序。这个权限和自更新行为可能触发 Google Play 的「设备与网络滥用」政策审核；如果主要通过 Google Play 分发，建议改用 Play In-App Updates，或在 Play 渠道构建中移除该权限与入口。GitHub Release / 官网 APK 渠道不受影响。

## 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 检查更新提示「网络连接失败」 | 清单地址不可访问、证书错误或 Web 端未配置 CORS |
| 清单 404 | 还没发过版，或 `R2_PUBLIC_BASE_URL` / 客户端地址不一致 |
| 清单 403 / 429 | 公开访问未开启、`r2.dev` 被限流，或 CDN 缓存了错误响应 |
| 下载后提示「安装包校验失败」 | R2 上的 APK 与清单不匹配，重新发版或清理 CDN 缓存 |
| 点击更新后跳到系统设置 | Android 8+ 首次安装需要允许「安装未知应用」，授权后回到应用点「继续安装」 |
| 系统提示「应用未安装」 | 新旧 APK 签名不一致、版本号没有增大，或安装包损坏 |
| 更新后仍提示有新版本 | 客户端版本号 / 构建号没有随发版更新，检查 `pubspec.yaml` 与 workflow 的 `--build-number` |
| 刚发版客户端还看不到 | 根清单有 60 秒缓存，稍等后重试；客户端请求也会带时间戳绕过缓存 |
