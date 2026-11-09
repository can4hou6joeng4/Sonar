// sonar-install：把一个短地址变成「一句话安装」入口。
// 只做三件事：给出可复制的安装话术、转发 llms.txt、提供 macOS 安装脚本与下载镜像。

const REPO = "can4hou6joeng4/Sonar";
const HOST = "sonar.bobochang.cn";
const RAW_LLMS = `https://raw.githubusercontent.com/${REPO}/main/llms.txt`;
const RELEASE_ASSET = `https://github.com/${REPO}/releases/latest/download/SonarMac.dmg`;

const SENTENCE = `请阅读 https://${HOST}/llms.txt 为我安装 Sonar`;

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    switch (pathname) {
      case "/":
      case "/install":
        return html();
      case "/llms.txt":
        return llms();
      case "/install.sh":
        return installScript();
      case "/SonarMac.dmg":
        return serve(request, env, "releases/SonarMac.dmg", RELEASE_ASSET, 86400, "application/x-apple-diskimage");
      case "/SonarMac.dmg.sha256":
        return serve(request, env, "releases/SonarMac.dmg.sha256", `${RELEASE_ASSET}.sha256`, 300, "text/plain; charset=utf-8");
      default:
        return new Response("404 Not Found\n", {
          status: 404,
          headers: { "content-type": "text/plain; charset=utf-8" },
        });
    }
  },
};

const text = (body, maxAge = 300, type = "text/plain; charset=utf-8") =>
  new Response(body, {
    headers: { "content-type": type, "cache-control": `public, max-age=${maxAge}` },
  });

async function llms() {
  const upstream = await fetch(RAW_LLMS, {
    cf: { cacheEverything: true, cacheTtl: 300 },
  }).catch(() => null);
  if (!upstream?.ok) {
    return text(
      [
        "# Sonar",
        "",
        "> 上游说明暂时不可读，请直接访问仓库按 README 构建或安装。",
        "",
        `- 仓库：https://github.com/${REPO}`,
        `- 发行包：https://github.com/${REPO}/releases/latest`,
        `- 本机镜像：https://${HOST}/SonarMac.dmg`,
        "",
      ].join("\n"),
      30,
    );
  }
  return new Response(upstream.body, {
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "public, max-age=300" },
  });
}

async function installScript() {
  const script = `#!/bin/sh
# Sonar macOS 安装脚本：下载 → 校验 → 挂载 → 复制 → 解除隔离 → 启动
# 可选环境变量：SONAR_INSTALL_DIR 指定安装目录；SONAR_NO_LAUNCH=1 只安装不启动
set -eu

MIRROR="https://${HOST}/SonarMac.dmg"
UPSTREAM="https://github.com/${REPO}/releases/latest/download/SonarMac.dmg"
DEST="${'${SONAR_INSTALL_DIR:-/Applications}'}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

[ "$(uname -s)" = "Darwin" ] || { echo "✗ 本脚本仅支持 macOS" >&2; exit 1; }

echo "→ 下载 SonarMac.dmg"
if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP_DIR/SonarMac.dmg" "$MIRROR"; then
  echo "  镜像不可用，改用 GitHub"
  curl -fL --retry 3 --retry-delay 2 -o "$TMP_DIR/SonarMac.dmg" "$UPSTREAM"
fi

if curl -fsL --retry 2 -o "$TMP_DIR/SonarMac.dmg.sha256" "$MIRROR.sha256" \\
   || curl -fsL --retry 2 -o "$TMP_DIR/SonarMac.dmg.sha256" "$UPSTREAM.sha256"; then
  echo "→ 校验 SHA-256"
  (cd "$TMP_DIR" && shasum -a 256 -c SonarMac.dmg.sha256) || { echo "✗ 校验失败" >&2; exit 1; }
else
  echo "  跳过校验：未取到 SHA-256 文件"
fi

echo "→ 安装到 $DEST"
VOLUME="$(hdiutil attach "$TMP_DIR/SonarMac.dmg" -nobrowse -readonly | awk -F'\\t' '/\\/Volumes\\//{print $NF}' | tail -1)"
[ -n "$VOLUME" ] || { echo "✗ 挂载失败" >&2; exit 1; }
osascript -e 'quit app "SonarMac"' >/dev/null 2>&1 || true
if [ -e "$DEST" ] && [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  echo "  目标目录不可写，改到 ~/Applications"
fi
mkdir -p "$DEST" || { echo "✗ 无法创建安装目录" >&2; exit 1; }
rm -rf "$DEST/SonarMac.app"
cp -R "$VOLUME/SonarMac.app" "$DEST/"
hdiutil detach "$VOLUME" >/dev/null

APP="$DEST/SonarMac.app"
xattr -cr "$APP"
if [ "${'${SONAR_NO_LAUNCH:-0}'}" != "1" ]; then
  echo "→ 启动 $APP"
  open "$APP"
fi
echo "✓ 完成：${'${APP}'} （菜单栏出现图标即安装成功）"
`;
  return text(script, 300, "text/x-shellscript; charset=utf-8");
}

const UA = `SonarInstall/1.0 (+https://${HOST})`;

// 优先从 R2 镜像取（GitHub 的发行包边缘偶发 504，Worker 直接回源并不可靠），
// 只有在镜像缺对象时才尽力回源 GitHub。
async function serve(request, env, key, fallbackUrl, maxAge, contentType) {
  const rangeHeader = request.headers.get("range");
  const object = env.MIRROR
    ? await env.MIRROR.get(key, rangeHeader ? { range: request.headers } : undefined).catch(() => null)
    : null;

  if (object) {
    const headers = new Headers({
      "content-type": object.httpMetadata?.contentType || contentType,
      "cache-control": `public, max-age=${maxAge}`,
      "accept-ranges": "bytes",
      etag: object.httpEtag,
    });
    let status = 200;
    if (object.range && rangeHeader) {
      const start = object.range.offset ?? 0;
      const length = object.range.length ?? Math.max(object.size - start, 0);
      headers.set("content-length", String(length));
      headers.set("content-range", `bytes ${start}-${start + length - 1}/${object.size}`);
      status = 206;
    } else {
      headers.set("content-length", String(object.size));
    }
    return new Response(request.method === "HEAD" ? null : object.body, { status, headers });
  }

  return mirror(request, fallbackUrl, maxAge);
}

// 回源 GitHub：重试三次，仍失败就如实返回 503，让客户端改走原始地址。
async function mirror(request, source, cacheTtl) {
  const method = request.method === "HEAD" ? "HEAD" : "GET";
  const range = request.headers.get("range");
  let upstream = null;
  for (let attempt = 0; attempt < 3 && !upstream; attempt++) {
    if (attempt) await new Promise((resolve) => setTimeout(resolve, 300 * attempt));
    const headers = new Headers({ "user-agent": UA, accept: "*/*" });
    if (range) headers.set("range", range);
    const response = await fetch(source, {
      method,
      headers,
      cf: { cacheEverything: true, cacheTtl },
    }).catch(() => null);
    if (response && (response.ok || response.status === 206)) upstream = response;
  }

  if (!upstream) {
    return new Response(
      JSON.stringify({ error: "upstream_unavailable", retry: true, origin: source }, null, 2) + "\n",
      {
        status: 503,
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
          "retry-after": "30",
        },
      },
    );
  }

  const out = new Headers(upstream.headers);
  out.delete("set-cookie");
  out.set("cache-control", `public, max-age=${cacheTtl}`);
  return new Response(method === "HEAD" ? null : upstream.body, {
    status: upstream.status,
    headers: out,
  });
}

function html() {
  const page = `<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sonar · 一句话安装</title>
<style>
  :root { color-scheme: dark }
  * { box-sizing: border-box }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 32px 20px;
         background: radial-gradient(120% 80% at 50% 0%, #12303a 0%, #070b0d 55%, #050608 100%);
         color: #e8f1f2; font: 16px/1.65 -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif }
  main { width: 100%; max-width: 640px }
  h1 { margin: 0 0 6px; font-size: 30px; letter-spacing: .01em }
  p.lead { margin: 0 0 26px; color: #9fb3b6 }
  .card { background: rgba(255,255,255,.045); border: 1px solid rgba(255,255,255,.09);
          border-radius: 16px; padding: 18px 18px 14px; margin-bottom: 16px }
  .card h2 { margin: 0 0 10px; font-size: 14px; font-weight: 600; color: #8fd3cf; letter-spacing: .04em; text-transform: uppercase }
  pre { margin: 0 0 12px; padding: 12px 14px; border-radius: 10px; background: #060b0d;
        border: 1px solid rgba(255,255,255,.07); overflow-x: auto;
        font: 13.5px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; color: #cfeedc; white-space: pre-wrap; word-break: break-word }
  button { border: 1px solid rgba(143,211,207,.35); background: rgba(143,211,207,.12); color: #b8f0ec;
           padding: 7px 14px; border-radius: 9px; font: inherit; font-size: 13px; cursor: pointer }
  button:hover { background: rgba(143,211,207,.2) }
  button[data-done="1"] { border-color: rgba(120,220,150,.5); color: #a7f3c4 }
  footer { margin-top: 22px; color: #6f8386; font-size: 13px }
  a { color: #8fd3cf }
</style>
<main>
  <h1>Sonar</h1>
  <p class="lead">在深水里靠声音辨路。原生 iOS / macOS 音乐播放器。</p>

  <div class="card">
    <h2>最省事：交给你的 AI</h2>
    <pre id="sentence">${SENTENCE}</pre>
    <button data-copy="sentence">复制这句话</button>
  </div>

  <div class="card">
    <h2>或者，直接跑安装脚本</h2>
    <pre id="cmd">curl -fsSL https://${HOST}/install.sh | sh</pre>
    <button data-copy="cmd">复制命令</button>
  </div>

  <footer>
    安装包为 ad-hoc 签名、未公证；脚本会校验 SHA-256 并解除 Gatekeeper 隔离。
    也可以直接下载 <a href="/SonarMac.dmg">SonarMac.dmg</a>，或从
    <a href="https://github.com/${REPO}/releases/latest">GitHub Releases</a> 获取。
    源码按 GPL-3.0 发布。
  </footer>
</main>
<script>
  for (const button of document.querySelectorAll("button[data-copy]")) {
    button.addEventListener("click", async () => {
      const target = document.getElementById(button.dataset.copy);
      try {
        await navigator.clipboard.writeText(target.textContent.trim());
        button.textContent = "已复制 ✓";
        button.dataset.done = "1";
      } catch {
        button.textContent = "请手动选择复制";
      }
      setTimeout(() => {
        button.textContent = button.dataset.copy === "cmd" ? "复制命令" : "复制这句话";
        delete button.dataset.done;
      }, 2000);
    });
  }
</script>
</html>
`;
  return new Response(page, {
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=300" },
  });
}
