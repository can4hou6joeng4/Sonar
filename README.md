<p align="center">
  <img src="Sonar/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" style="border-radius: 26px;" alt="Sonar Icon" />
</p>

<h1 align="center">Sonar</h1>

<p align="center"><strong>🐋 在深水里靠声音辨路。原生极简 iOS 音乐播放器，让搜索、收藏与聆听回归纯粹。</strong></p>

<div align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&logo=apple&logoColor=white" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9%2B-FA7343?style=flat-square&logo=swift&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-3E82F7?style=flat-square" />
  <img alt="SwiftData" src="https://img.shields.io/badge/Storage-SwiftData-5E5CE6?style=flat-square" />
  <img alt="License" src="https://img.shields.io/badge/License-GPL--3.0-34C759?style=flat-square" />
  <img alt="No Ads" src="https://img.shields.io/badge/AdFree-100%25-brightgreen?style=flat-square" />
  <img alt="Zero Tracking" src="https://img.shields.io/badge/Privacy-Zero%20Tracking-blueviolet?style=flat-square" />
</div>

<p align="center">
  <a href="#-特征">特征</a> ·
  <a href="#-快速开始与安装">快速开始</a> ·
  <a href="#-播放架构与兜底流程">播放架构</a> ·
  <a href="#%EF%B8%8F-从源码构建">从源码构建</a> ·
  <a href="#-数据与凭据管理">数据与凭据</a> ·
  <a href="#-免责声明与合规说明">免责声明</a> ·
  <a href="#-致谢与开源协议">开源协议</a>
</p>

---

## 🎐 特征

- 🎐 **极简克制**：纯粹原生 SwiftUI 打造，零广告、无开屏推销、无多余社交推荐，启动即听，回归音乐本真
- 🔎 **双源探索**：深度聚合网易云与 QQ 双主流音源，歌曲与歌手检索独立呈现，支持艺术家与专辑顺畅探索
- 🛡️ **坚固兜底**：智能多级播放管线（官方源高品 → 跨源同名匹配 → 公共音源流兜底），凭据失效依然稳定播放
- 🎨 **流光氛围**：实时智能封面动态取色，明暗外观与毛玻璃光影相映成趣，沉浸式黑胶唱片旋转动效
- 🎵 **逐字歌词**：毫秒级同步平滑逐字滚动，支持全屏歌词流览、锁屏封面与系统后台播控
- 💾 **本地优先**：纯本地 SwiftData 离线歌单管理与持久化存储，支持通过“文件”导出/导入 JSON 无损备份并智能去重

> **说明**：Sonar 仅在本地管理与保存您的歌单及歌曲元数据索引。歌单备份不包含音频原始文件，亦不代表提供离线下载服务。

---

## 📲 快速开始与安装

运行环境需 **iOS 17.0 或更高版本**。

> [!NOTE]
> 本项目遵循**纯开源代码分发**原则，仓库**不提供任何预编译安装包或个人自用 IPA**。用户可通过下方指南自行拉取源码并在本地打包专属于自己的 IPA 文件：

| 安装方式 | 适合场景 | 流程说明 |
| :--- | :--- | :--- |
| 🦖 **TrollStore（巨魔）** | 适用支持巨魔的 iOS 设备 | 本地编译生成未签名 `Sonar.ipa` 后，通过 AirDrop 或系统文件直接导入 TrollStore 永久使用 |
| 📲 **个人自签工具** | 普通未越狱 iOS 设备 | 使用本地打包生成的 `Sonar.ipa`，通过 AltStore / Sideloadly / 个人免费证书重签载入 |
| 🛠️ **Xcode 联机直装** | 拥有 Mac 的用户 / 开发者 | 打开工程并连接真机，配置个人免费开发者签名后，直接 `⌘R` 联机运行 |

### 使用提示

1. **音乐探索与收藏**：在发现页或搜索框输入曲目/歌手，轻触即可播放；在播放器面板或列表轻点爱心或操作菜单即可加入个人歌单。
2. **歌单导入与导出**：
   - 进入 **设置 → 歌单备份**；
   - **导出歌单**：将当前资料库中的歌曲数据打包为标准化 JSON 备份文件保存至“文件”App 或分享；
   - **导入歌单**：读取备份文件，自动增量追加新歌曲，已存在的歌曲将自动去重跳过，保证资料库纯净安全。

---

## 🔀 播放架构与兜底流程

为了在无商业服务器支持的情况下提供尽可能稳定连续的听歌体验，Sonar 采用了客户端智能多级回退与音质阶梯降级策略：

```mermaid
flowchart TD
    A[用户点播曲目] --> B{主音源可用且有凭据?}
    B -- 是 --> C[官方主音源解析 (FLAC / 320k)]
    B -- 否 / 解析失败 --> D[智能回退解析器]
    D --> E{跨音源同名同歌手检索}
    E -- 匹配成功 --> F[备用音源解析播放]
    E -- 匹配失败 / 播放异常 --> G[公共流媒体兜底 (咪咕 320k 优先)]
    G -- 解析失败 --> H[轻量公共流兜底 (酷我 128k 保底)]
    H -- 成功 --> I[稳定顺畅播放]
    C --> I
    F --> I
    G --> I
    H -- 失败 --> J[提示播放不可用并保留原始诊断信息]
```

- **第一级（官方高品）**：优先调用用户配置的官方音源凭据，保障无损 FLAC 与 320kbps 高音质音频流；
- **第二级（跨源互补）**：主音源无版权或失效时，自动根据歌曲标题与歌手精确跨源匹配；
- **第三级（公共流保底）**：串行依次请求公网标准化流解析通道，以极小网络开销完成播放救场。

---

## 🛠️ 从源码构建

### 开发环境要求

| 组件 / 工具 | 最低要求 | 作用说明 |
| :--- | :--- | :--- |
| **macOS** | Sonoma 14.0+ | 开发主机系统 |
| **Xcode** | 15.0+ (已验证 16 系列) | 包含 iOS 17 SDK 的开发集成环境 |
| **Node.js** | 18.0.0+ | 用于构建音源 JavaScript 资源与配置生成 |
| **CocoaPods / SPM** | 原生 SPM | 纯 SwiftPM 依赖管理，开箱即用无额外包管理器负担 |

### 1. 检出代码与构建音源运行时

音源解析引擎采用 JavaScriptCore 原生内嵌驱动。修改 `js-source/` 后需执行打包：

```sh
git clone https://github.com/can4hou6joeng4/Sonar.git
cd Sonar

# 安装依赖并生成内嵌音源运行时
npm ci
npm run build:source
```

### 2. 打开 Xcode 工程

双击打开 `Sonar.xcodeproj`，在 Xcode 顶部选择 **Sonar** Scheme 和您的调试目标（iPhone 真机或模拟器），点击 **Run (⌘R)** 即可。

### 3. 本地打包 IPA 文件

执行以下命令即可在本地一键编译并封装生成未签名的 `Sonar.ipa`（可直接用于 TrollStore 或自签工具）：

```sh
# 1. 编译生成 Release 归档
xcodebuild -project Sonar.xcodeproj -scheme Sonar \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Sonar.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''

# 2. 封装为标准 IPA 文件
mkdir -p build/Payload
cp -R build/Sonar.xcarchive/Products/Applications/Sonar.app build/Payload/
cd build && zip -qr Sonar.ipa Payload && rm -rf Payload && cd ..

# 产物即为 build/Sonar.ipa
```

---

## 🔐 数据与凭据管理

### 本地资料库与数据安全

- 歌单完全保存在本地 SwiftData 容器中，不依赖任何第三方云端账户，杜绝隐私泄漏风险；
- 资料库异常恢复页支持导出**原始资料文件**，用于极端情况下的底层数据修复。

### 可选音源环境变量

新检出的开源仓库默认不包含任何第三方私有凭据，但已内置公共流解析回退。您可通过环境变量注入增强凭据以开启更多源的高音质通道：

| 环境变量 | 作用与对应通道 |
| :--- | :--- |
| `SONAR_WY_TOKEN` | 网易云音乐接口访问鉴权凭据 |
| `SONAR_CHKSZ_KEY` | ChKSz 接口解析凭据 |

执行构建时，`scripts/generate-build-config.mjs` 会读取上述环境变量并生成 `BuildCredentials.json`（已加入 `.gitignore`）。**请勿公开提交或向公众分发包含个人真实凭据的二进制包。**

---

## ⚖️ 免责声明与合规说明

> [!IMPORTANT]
> **请在阅读并理解以下条款后再使用或参与本项目：**

1. **非商业研究用途**：Sonar 为个人兴趣与原生 iOS 架构探索而创建的开源项目，仅用于技术学习、SwiftUI/SwiftData 实践及非商业性研究交流，严禁将本项目及其衍生版本用于任何商业牟利行为。
2. **纯客户端架构与零数据存储**：本项目为纯客户端应用程序，无任何自建后端或中转服务器；本项目不提供音频存储、不分发受版权保护的音视频文件、不持有任何音频媒体数据。播放过程中涉及的音频流、专辑封面与歌词等数据，均由客户端根据用户指令向第三方服务提供方发起公开请求获取。
3. **知识产权归属**：所有由音源返回的歌曲、歌词、专辑图文及商标等合法知识产权均归属于其各自的原始版权方、歌手、唱片公司或对应在线音乐服务平台。
4. **用户义务**：使用者应遵循所在地区的相关法律法规，尊重音乐版权。体验测试完毕后请在 24 小时内自行删除相关解析与缓存文件，支持并购买正版音乐服务。
5. **侵权与异议处理**：若任何版权方或个人认为本项目的开源代码对您的合法权益造成了影响，请通过 GitHub Issue 或电子邮件联系维护者，我们将第一时间积极配合下线或调整相关内容。

---

## 📄 致谢与开源协议

### 致谢

- 感谢 [lx-music-mobile](https://github.com/lyswhut/lx-music-mobile) 及其开源生态，本项目的音源解析脚本在设计时参考了其部分开源实践。
- 第三方依赖与开源库许可声明请查阅 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [LICENSES/](LICENSES/) 目录。

### 开源许可证

本项目自有代码遵循 **[GNU General Public License v3.0 (GPL-3.0)](LICENSE)** 协议开源。
您可以在遵守 GPL-3.0 协议条款的前提下自由使用、修改和衍生本代码，但任何衍生与再分发必须保持同等许可证开源。
