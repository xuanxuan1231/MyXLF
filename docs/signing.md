# 签名配置指南

Release 工作流支持可选的 Android / iOS 正式签名。未配置时：

- Android 回退到 debug 签名（仍可构建，但只适合内部测试）。
- iOS 构建未签名 IPA，用户需要用自己的 Apple ID 重新签名后侧载安装。

## Android

### 1. 创建 keystore

需要已安装 JDK（`keytool` 随 JDK 提供）。在安全目录执行：

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -alias upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=MyXLF, OU=Mobile, O=HelloSWX, L=Shanghai, ST=Shanghai, C=CN"
```

执行后会交互式要求输入：

- keystore 密码（`storePassword`）
- 密钥密码（`keyPassword`，可直接回车沿用 keystore 密码）

记下密码和 alias（示例中为 `upload`）。

> ⚠️ keystore 一旦丢失，就无法再发布可覆盖安装的更新。请离线备份，且不要提交到仓库（`*.jks` / `*.keystore` / `key.properties` 已在 `.gitignore` 中）。

### 2. 转成 Base64

Linux：

```bash
base64 -w0 upload-keystore.jks > upload-keystore.b64
```

macOS：

```bash
base64 -i upload-keystore.jks | tr -d '\n' > upload-keystore.b64
```

Windows PowerShell：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) |
  Set-Content -NoNewline upload-keystore.b64
```

### 3. 配置 GitHub Secrets

在仓库 **Settings → Secrets and variables → Actions → Secrets** 中添加：

| Secret | 值 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `upload-keystore.b64` 的内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名，例如 `upload` |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

也可以用 `gh` 命令：

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < upload-keystore.b64
gh secret set ANDROID_KEYSTORE_PASSWORD   # 交互式输入
gh secret set ANDROID_KEY_ALIAS --body "upload"
gh secret set ANDROID_KEY_PASSWORD        # 交互式输入
```

上传完成后删除本地的 `.b64` 文件。

### 4. 本地构建已签名 Release

```bash
cp android/key.properties.example android/key.properties
```

编辑 `android/key.properties`：

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=你的keystore密码
keyAlias=upload
keyPassword=你的密钥密码
```

`storeFile` 可以写绝对路径，也可以写相对于 `android/` 目录的路径。

验证签名：

```bash
fvm flutter build apk --release
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

或查看 keystore 信息：

```bash
keytool -list -v -keystore upload-keystore.jks -alias upload
```

---

## iOS

已签名的 iOS 安装包必须由 Apple 证书签名，因此要让工作流直接产出可安装的 IPA，需要加入 [Apple Developer Program](https://developer.apple.com/programs/)（个人/公司账号每年 99 美元）。

没有开发者账号也可以发布 **未签名 IPA**：工作流会构建 `MyXLF-<version>-unsigned.ipa`，用户使用 AltStore、Sideloadly 等工具和自己的 Apple ID 重新签名后侧载安装。详见下方「没有 Apple Developer Program：未签名 IPA 与侧载」。

项目当前的 Bundle ID 是 `top.helloswx.xlf`。

### 1. 创建 App ID

1. 登录 [Apple Developer](https://developer.apple.com/account)。
2. 进入 **Certificates, Identifiers & Profiles → Identifiers**。
3. 点击 **+**，选择 **App IDs → App**。
4. Description 填 `MyXLF`，Bundle ID 选择 **Explicit**，填写 `top.helloswx.xlf`。
5. 保存。

如果该 Bundle ID 已存在可跳过。

### 2. 创建 Apple Distribution 证书（.p12）

推荐直接在 Xcode 中创建：

1. 打开 **Xcode → Settings → Accounts**，添加 Apple ID。
2. 选中账号，点击 **Manage Certificates…**。
3. 点击左下角 **+**，选择 **Apple Distribution**。
4. 创建完成后，打开「钥匙串访问 / Keychain Access」。
5. 在 **login → 我的证书** 中找到 `Apple Distribution: 你的名字 (TEAMID)`。
6. 展开证书，**同时选中证书和私钥**，右键 → **导出**，格式选择 `.p12`，设置导出密码。

> `.p12` 必须包含私钥，否则无法签名。导出的密码就是 `IOS_CERTIFICATE_PASSWORD`。

如果使用开发者网站手动创建：

1. 钥匙串访问 → 证书助理 → 从证书颁发机构请求证书，保存 CSR。
2. Developer → Certificates → **+** → **Apple Distribution**，上传 CSR。
3. 下载 `.cer` 并双击安装到钥匙串。
4. 按上面的方法从钥匙串导出 `.p12`。

### 3. 创建描述文件（.mobileprovision）

1. Developer → **Profiles** → **+**。
2. 选择 **Distribution → App Store**（直装测试则选 **Ad Hoc**）。
3. 选择 App ID `top.helloswx.xlf`。
4. 选择刚创建的 Apple Distribution 证书。
5. 填写 Profile Name，例如 `MyXLF App Store`。
6. 生成并下载 `.mobileprovision`。

这个 **Profile Name** 就是 `IOS_PROVISIONING_PROFILE_SPECIFIER`，不是文件名，也不是 UUID。

- **App Store**：上传 TestFlight / App Store。
- **Ad Hoc**：可直接安装到已登记 UDID 的设备，需要把 `IOS_EXPORT_METHOD` 设为 `ad-hoc`。
- 描述文件必须与 Bundle ID、证书匹配；证书或描述文件更新后要同步更新 Secrets。

### 4. 获取 Team ID

Developer → **Membership details** → **Team ID**，形如 `ABCDE12345`（10 位）。

### 5. 转成 Base64 并配置 Secrets

macOS：

```bash
base64 -i certificate.p12 | tr -d '\n' > certificate.p12.b64
base64 -i MyXLF_App_Store.mobileprovision | tr -d '\n' > profile.b64
```

设置 Secrets：

```bash
gh secret set IOS_CERTIFICATE_BASE64 < certificate.p12.b64
gh secret set IOS_CERTIFICATE_PASSWORD       # .p12 导出密码
gh secret set IOS_PROVISIONING_PROFILE_BASE64 < profile.b64
gh secret set IOS_PROVISIONING_PROFILE_SPECIFIER --body "MyXLF App Store"
gh secret set IOS_TEAM_ID --body "ABCDE12345"
```

| Secret | 说明 |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | `.p12` 证书的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 Base64 |
| `IOS_PROVISIONING_PROFILE_SPECIFIER` | 描述文件的 **Name** |
| `IOS_TEAM_ID` | Apple Developer Team ID |

上传后删除本地的 `.b64`、`.p12` 和 `.mobileprovision`（按需保留备份）。

### 6. 可选：切换导出方式

默认导出 App Store 包。若要做 Ad Hoc 直装，先创建 Ad Hoc 描述文件，然后设置仓库变量：

```bash
gh variable set IOS_EXPORT_METHOD --body "ad-hoc"
```

支持的值：

- `app-store`（默认，App Store / TestFlight）
- `ad-hoc`（已登记设备直装）
- `enterprise`（企业分发）

修改描述文件类型后，记得同步更新 `IOS_PROVISIONING_PROFILE_BASE64` 和 `IOS_PROVISIONING_PROFILE_SPECIFIER`。

### 7. 验证 IPA

推送标签后，在 Actions 的 Release 构建中下载：

- 配置了 5 个 iOS Secrets：`MyXLF-<version>.ipa`（已签名）
- 没有配置任何 iOS Secrets：`MyXLF-<version>-unsigned.ipa`（未签名，需要用户自行签名）

App Store 包可以：

- 用 **Transporter** 上传到 App Store Connect，然后通过 TestFlight 分发；或
- 使用 App Store Connect API Key 上传：

```bash
xcrun altool --upload-app \
  --type ios \
  -f MyXLF-1.0.0.ipa \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"
```

Ad Hoc 包可以通过 Apple Configurator、Xcode Devices 窗口或第三方工具安装到已登记设备。

## 没有 Apple Developer Program：未签名 IPA 与侧载

没有开发者账号时，工作流会自动构建：

```text
MyXLF-<version>-unsigned.ipa
```

它本质上是 `Payload/Runner.app` 的压缩包，**没有任何 Apple 签名，不能直接安装**。iOS 会拒绝安装未签名或签名无效的 App，所以用户必须用自己的 Apple ID 重新签名。

> Flutter 3.47 会把项目的最低 iOS 版本迁移到 15.0，iOS 15 以下的设备无法安装该 IPA。
>
> 如果 `top.helloswx.xlf` 这个 Bundle ID 已被原开发者占用，AltStore / Sideloadly 需要修改 Bundle ID 后才能用免费 Apple ID 签名。

### 用户如何安装

#### 方式一：AltStore / SideStore

适合普通用户，免费 Apple ID 即可：

1. 在 Windows / macOS 上安装 [AltServer](https://altstore.io/)。
2. 用数据线连接 iPhone，通过 AltServer 安装 AltStore 到手机。
3. 打开 AltStore → **My Apps** → 左上角 `+`，选择下载的 `-unsigned.ipa`。
4. 输入自己的 Apple ID 和密码，AltStore 会用免费开发者证书重签并安装。
5. 首次运行前，在 iPhone **设置 → 通用 → VPN 与设备管理** 中信任该开发者证书。
6. 免费证书 7 天过期，AltStore 连接同一 Wi-Fi 时会自动续签；SideStore 可以脱离电脑续签。

#### 方式二：Sideloadly

1. 下载 [Sideloadly](https://sideloadly.io/)（Windows / macOS）。
2. 连接 iPhone，把 `-unsigned.ipa` 拖进 Sideloadly。
3. 输入 Apple ID，点击 Start。
4. 安装完成后在 **设置 → 通用 → VPN 与设备管理** 中信任证书。

#### 方式三：Xcode

有 Mac 的话，也可以直接用 Xcode 打开项目，把 Team 设置为自己的 Personal Team，连接手机后 `flutter run --release` 或 Archive 安装。这种方式同样受免费证书 7 天限制。

#### 方式四：TrollStore

TrollStore 可以在部分存在 CoreTrust 漏洞的 iOS 版本上直接安装未签名 IPA，且永久有效。但它只支持特定 iOS 版本/设备组合（通常为 iOS 14.0–17.0 的某些版本），新系统无法使用，不能作为通用方案。

### 免费 Apple ID 的限制

- 签名 **7 天后过期**，需要重新签名。
- 同时最多保留 **3 个**自签 App。
- 每周最多注册 10 个 App ID。
- 不能上传 App Store / TestFlight，也不能做 Ad Hoc 分发。

### 付费开发者账号

- 证书有效期 1 年。
- 可上传 App Store / TestFlight。
- Ad Hoc 最多 100 台设备。
- 适合正式长期分发。

### 不建议的做法

不要购买或使用来路不明的「企业证书」「共享证书」：这类证书随时可能被 Apple 吊销，且把 Apple ID 密码交给第三方签名服务存在账号风险。

## 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| `No profiles for 'top.helloswx.xlf' were found` | 描述文件 Bundle ID 不匹配，或 `IOS_PROVISIONING_PROFILE_SPECIFIER` 填的不是 Profile Name |
| `Provisioning profile ... doesn't include signing certificate` | 描述文件没有包含当前 `.p12` 中的证书，重新生成描述文件 |
| `密钥链中未找到 Apple Distribution 证书` | `.p12` 不是 Apple Distribution 证书，或导出时没有包含私钥 |
| `IOS_PROVISIONING_PROFILE_SPECIFIER 应为描述文件名称...` | Secret 填成了文件名/UUID，改为描述文件的 Name |
| 未配置 iOS Secrets 时没有签名 IPA | 正常行为，会生成 `-unsigned.ipa`，供用户自行侧载签名 |
| 未签名 IPA 无法直接安装 | iOS 必须校验签名，用 AltStore / Sideloadly / Xcode 重签后再安装 |
| 侧载后 7 天打不开 | 免费 Apple ID 证书过期，重新签名/续签 |
| TrollStore 装不上 | 当前 iOS 版本不支持 CoreTrust 漏洞，改用 AltStore/Sideloadly |
| iOS Secrets 只配置了一部分 | 工作流会报错并列出缺少的名称 |
| 证书过期 | 重新创建/下载证书和描述文件，更新对应 Secrets |
