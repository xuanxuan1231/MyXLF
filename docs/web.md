# Web 版构建与部署

Web 版与其他平台共用同一套 Dart 代码，平台差异通过条件导入隔离：

| 能力 | 移动端 / 桌面端 | Web |
| --- | --- | --- |
| 保存答卷图片 | 系统相册 / 下载目录 | 浏览器下载 |
| 分享答卷图片 | 系统分享面板 | Web Share API，不支持时回退为下载 |
| 会话 Cookie | 本地 CookieJar | 浏览器自动管理 |
| 自签名证书 | 允许忽略证书校验 | 浏览器不允许绕过，必须使用受信任证书 |
| 设备标识 | ANDROID_ID / IDFV | 无，使用 PostHog 随机 UUID |

## 构建

```bash
fvm flutter build web --release
```

构建产物在 `build/web`。如果 API 与网页不同源，需要在构建时指定地址：

```bash
fvm flutter build web --release \
  --dart-define=XLF_BASE_URL=https://your-host/tqweb
```

`XLF_BASE_URL` 不含末尾斜杠，默认值为测试平台
`https://test.k12media.cn:8000/tqweb`。

## 部署要求

### 1. 必须使用 HTTPS

`flutter_secure_storage` 的 Web 实现基于 WebCrypto，浏览器只在安全上下文
（HTTPS 或 `localhost`）中提供该能力。使用 HTTP 部署时账号密码无法持久化。

### 2. API 必须同源，或由服务端开启 CORS

浏览器的跨域请求受同源策略限制。当前测试平台
（`test.k12media.cn:8000`）的响应**没有 `Access-Control-Allow-Origin`**，
因此网页版直接访问该地址时，登录与数据请求都会被浏览器拦截。

推荐做法是把 `build/web` 与 API 部署在同一域名下，用反向代理转发 `/tqweb`：

```nginx
server {
    listen 443 ssl;
    server_name app.example.com;

    root /var/www/mylf;      # build/web 的内容
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /tqweb/ {
        proxy_pass https://test.k12media.cn:8000/tqweb/;
        proxy_set_header Host test.k12media.cn:8000;
        proxy_set_header Referer https://test.k12media.cn:8000/tqweb/login.jsp;
        proxy_cookie_domain test.k12media.cn app.example.com;
    }
}
```

构建时使用 `--dart-define=XLF_BASE_URL=https://app.example.com/tqweb`。
代理对 `Referer` 的重写是必需的：平台的 DWR 接口会校验 `Referer`，而浏览器
不允许前端脚本自定义该请求头。

如果无法做同源代理，则必须让平台在响应中返回
`Access-Control-Allow-Origin` 与 `Access-Control-Allow-Credentials`，并允许
`Cookie` 跨域携带。

### 3. 登出与会话

Web 端的会话 Cookie 由浏览器管理，`JSESSIONID` 通常是 `HttpOnly`，前端脚本
无法删除。退出登录时应由服务端销毁会话（或在代理层清理 Cookie），否则刷新
页面后可能仍处于登录状态。

## 已知限制

- 保存图片等同于浏览器下载，不会进入系统相册。
- 分享依赖浏览器对 Web Share API 的支持（移动端浏览器通常支持，桌面端多数
  回退为下载）。
- 没有 ANDROID_ID / IDFV，遥测的去重 ID 由 PostHog 生成并保存在浏览器本地。
