<div align="center">
  <img src="Sonar/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="Sonar 图标" width="120" height="120" />
  <h1>Sonar</h1>
  <p><em>🐋 在深水里靠声音辨路。</em></p>
  <p>一款原生 iOS 音乐播放器，让搜索、收藏与聆听回到音乐本身。</p>
</div>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17%2B-111111?style=flat-square&logo=apple" alt="iOS 17 及以上" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-orange?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Runtime-JavaScriptCore-blue?style=flat-square" alt="JavaScriptCore" />
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> ·
  <a href="#安装与使用">安装与使用</a> ·
  <a href="#从源码构建">从源码构建</a> ·
  <a href="#数据与播放凭据">数据与播放凭据</a> ·
  <a href="#致谢">致谢</a>
</p>

---

## 功能特性

- 🔎 **从一首歌开始**：网易与 QQ 双音源搜索，歌曲与歌手结果独立展示，继续探索歌手和专辑。
- 🎧 **连贯的播放体验**：待播放队列、播放模式、音质选择与后台播放；加载和切歌遵循最新操作；支持多级播放回退与自动兜底。
- 🎵 **跟着歌词听**：同步逐字歌词，搭配黑胶封面和沉浸式播放界面。
- 🎨 **随封面变化的色彩**：封面取色与明暗外观，让播放器保留自己的氛围。
- 💾 **留住喜欢的音乐**：个人歌单、重命名、收藏与移除；通过系统“文件”导出备份、合并导入并跳过重复歌曲。
- 🛟 **为长期使用留余地**：封面缓存有容量与过期控制；资料库打开失败时，可重试或导出原始资料文件。

> Sonar 保存的是歌单与歌曲信息。歌单备份不包含音频文件，也不代表离线下载。

## 安装与使用

需要 **iOS 17 或更高版本**。

当前以自行构建、个人设备重签验证为主。已有 `Sonar.ipa` 时，需要使用自己的证书与适用的描述文件重签后安装；无签名归档不能直接安装到手机。

进入 App 后，可以搜索歌曲、查看歌手与专辑，将喜欢的歌曲收藏到个人歌单。歌单备份入口位于**设置 → 歌单备份**：

- **导出歌单**：将歌曲信息保存为 JSON 文件。
- **导入歌单**：把备份中的新歌曲追加到现有歌单，重复歌曲自动跳过。

小组件扩展保留在工程中；当前没有将个人重签环境下的小组件表现作为已通过的真机验收项。

## 从源码构建

### 开发环境

| 工具 | 要求 |
| --- | --- |
| macOS / Xcode | 已使用 Xcode 26 系列验证的 iOS 开发环境 |
| Node.js | 18 或更高版本，用于音源资源与构建配置生成 |
| 签名 | 真机安装时使用自己的证书与描述文件 |

### 打开工程

打开 `Sonar.xcodeproj`，选择 **Sonar** Scheme 和目标设备后构建。共享工程包含主 App 与小组件扩展。

音源 JavaScript 资源已随源码保存。修改 `js-source/` 后，执行以下命令重新生成：

```sh
npm ci
npm run build:source
```

`package.json` 与 `package-lock.json` 保留音源构建所需的依赖信息；无需把 `node_modules/` 加入仓库。

### 真机 Release 归档

```sh
xcodebuild -project Sonar.xcodeproj -scheme Sonar \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Sonar.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

这条命令生成无签名 `.xcarchive`。封装 IPA 时，将归档中的 `Products/Applications/Sonar.app` 放入 `Payload/Sonar.app` 后压缩，再进行个人签名与安装。

`project.yml` 可用于生成共享工程。若使用 XcodeGen，建议先在临时目录生成并检查差异，再更新正式工程。

## 数据与播放凭据

### 歌单与备份

歌单保存在本地资料库中。导入采用追加合并，不删除现有歌曲；无效文件会被拒绝，保存失败会撤销此次导入。

资料库恢复页导出的**原始资料文件**用于故障恢复，与设置中导出的**歌单备份**格式不同，不能相互替代。

### 可选音源凭据

搜索与播放需要访问对应音源服务。部分播放路径或音质需要额外凭据，可通过构建环境提供：

| 环境变量 | 用途 |
| --- | --- |
| `SONAR_WY_TOKEN` | 网易播放凭据 |
| `SONAR_CHKSZ_KEY` | ChKSz 接口凭据 |

共享入口 `scripts/generate-build-config.mjs` 在未提供凭据时生成空配置，因此新检出的仓库也能完成构建。实际歌曲与音质可用性仍取决于音源返回。内置播放管线支持多级回退策略（官方源 → 跨源同名匹配 → 公共音频流兜底），在专属凭据未配置或过期时提供基础播放保障。

若本机存在未跟踪的 `scripts/generate-build-credentials.mjs`，构建会优先使用它。真实凭据及生成的 `BuildCredentials.json` 不提交到仓库。**包含真实凭据的安装包仅供个人设备使用，不公开分发。**

## 技术组成

| 部分 | 实现 |
| --- | --- |
| 原生界面 | SwiftUI |
| 播放与系统音频 | AVFoundation |
| 本地资料库 | SwiftData |
| 音源运行时 | JavaScriptCore |
| 音源资源构建 | Node.js / esbuild |

共享仓库保留应用源码、资源、工程与必要构建脚本。本地测试和个人开发工具单独维护，不是构建共享 App 的前提。

## 致谢

音源实现参考并复用了 [lx-music-mobile](https://github.com/lyswhut/lx-music-mobile) 的相关代码，感谢上游项目的开源工作。第三方代码与依赖的使用、修改和分发需保留并遵循各自适用的许可声明。

### 许可与归属

第三方源码和依赖的许可证、版权声明与来源信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [LICENSES/](LICENSES/)。构建的音源资源会携带这些声明。

Sonar 自有代码的对外许可证尚未确定；上述第三方许可证不应被理解为整个项目的统一授权。
