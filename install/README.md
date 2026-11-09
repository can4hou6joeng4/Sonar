# Sonar 安装入口（Cloudflare Worker）

把「一句话安装」收敛到短域名 <https://sonar.bobochang.cn>。Worker 只做转发与展示，不存用户数据。

| 路径 | 行为 |
| --- | --- |
| `/`、`/install` | 安装说明页，含可复制的一句话与安装命令 |
| `/llms.txt` | 转发仓库根 `llms.txt`（边缘缓存 5 分钟），上游失败时返回最小说明 |
| `/install.sh` | macOS 安装脚本：下载 → SHA-256 校验 → 挂载 → 复制 → 解除隔离 → 启动 |
| `/SonarMac.dmg` | 最新 macOS 安装包镜像，来自 R2 桶 `sonar-mirror`，支持 Range / HEAD |
| `/SonarMac.dmg.sha256` | 对应校验文件 |

## 为什么镜像放在 R2

GitHub 的 `/releases/download/...` 在部分网络会间歇返回 504（实测同一时刻 `gh release download` 走 API 仍正常）。
从 Worker 直接回源同样失败，因此安装包以 R2 为准，GitHub 仅在镜像缺对象时作为兜底；缺对象且回源失败会如实返回 503，而不是把错误包装成下载成功。

## 部署

```sh
# 令牌从 ~/.env 读取，不要写进命令历史，也不要提交
CLOUDFLARE_API_TOKEN=$(grep -E '^CLOUDFLARE_API_TOKEN=' ~/.env | tail -1 | cut -d= -f2-) \
  npx wrangler deploy --config install/wrangler.jsonc
```

自定义域名由 `wrangler.jsonc` 的 `routes[].custom_domain` 自动创建 DNS 记录，无需手工加 CNAME。

## 发布新版本后同步镜像

```sh
export CLOUDFLARE_API_TOKEN=$(grep -E '^CLOUDFLARE_API_TOKEN=' ~/.env | tail -1 | cut -d= -f2-)
./install/upload-mirror.sh          # 默认取 latest，也可传 tag：./install/upload-mirror.sh v1.0.2
```

脚本优先用 `gh release download` 取包（走 API，比网页下载稳定），上传后会自动比对线上 `.sha256`。

## 本地验证

```sh
# Worker 语法与三端点（不需要部署）
node --check install/worker.mjs

# 安装脚本的完整流程，装到临时目录且不启动
curl -s https://sonar.bobochang.cn/install.sh | SONAR_INSTALL_DIR=/tmp/sonar-test SONAR_NO_LAUNCH=1 sh
```

`SONAR_INSTALL_DIR` 指定安装目录（默认 `/Applications`，不可写时回落到 `~/Applications`），
`SONAR_NO_LAUNCH=1` 只安装不启动，便于回归测试。

## 注意

- 修改仓库根 `llms.txt` 后最多 5 分钟内自动生效，无需重新部署 Worker。
- 镜像对象是固定键 `releases/SonarMac.dmg`，发布新版本需重跑 `upload-mirror.sh`，否则线上仍是旧包。
- `/SonarMac.dmg` 可被 Cloudflare 边缘缓存 1 天；重跑上传后刷新一次即可，必要时带查询串绕开缓存。
