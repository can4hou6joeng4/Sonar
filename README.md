<p align="center">
  <img src="Sonar/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="120" alt="Sonar" />
</p>

<h1 align="center">Sonar</h1>

<p align="center"><strong>🐋 在深水里靠声音辨路。</strong></p>
<p align="center">原生 iOS 与 macOS 音乐播放器，让搜索、收藏与聆听回归纯粹。</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/SwiftUI-FA7343?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-34C759?style=for-the-badge" alt="GPL-3.0" /></a>
  <a href="https://linux.do/"><img src="https://img.shields.io/badge/LINUX_DO-Community-1A1A1A?style=for-the-badge" alt="LINUX DO 社区" /></a>
</p>

<p align="center">
  <a href="#界面预览">界面预览</a> ·
  <a href="#功能">功能</a> ·
  <a href="#运行与安装">运行与安装</a> ·
  <a href="#从源码构建">从源码构建</a> ·
  <a href="#数据与音源">数据与音源</a> ·
  <a href="#致谢">致谢</a>
</p>

## 界面预览

### iOS

<p align="center">
  <a href="assets/previews/ios-main.png"><img src="assets/previews/ios-main.png" width="900" alt="iOS 歌单、搜索与播放器实图" /></a>
</p>

<p align="center">
  <a href="assets/previews/ios-details.png"><img src="assets/previews/ios-details.png" width="900" alt="iOS 同步歌词、设置与歌单备份实图" /></a>
</p>

### macOS

<p align="center">
  <a href="assets/previews/macos.png"><img src="assets/previews/macos.png" width="900" alt="macOS 状态栏面板、播放列表与顶部播放器实图" /></a>
</p>

<p align="center">
  <a href="assets/previews/macos-removal.png"><img src="assets/previews/macos-removal.png" width="600" alt="macOS 取消收藏确认：歌曲行高亮、已移除标记与带歌名的提示" /></a>
</p>

## 功能

- **双源搜索**：接入网易云与 QQ，按歌曲、歌手、歌单分类检索。
- **封面与歌词**：播放页随封面取色，支持明暗外观、同步歌词与逐字高亮；缺少逐字时间时会明确标注合成效果。
- **本地歌单**：用 SwiftData 保存收藏和歌曲信息，支持 JSON 导入、导出与重复歌曲去重。
- **播放队列**：支持下一首播放、加入待播，以及随机、单曲循环、顺序播放和列表循环。
- **Mac 随手播控**：状态栏选歌面板与顶部播放器共享播放、收藏状态，支持悬停展开、封面、歌词、进度和音量控制；取消收藏提供确认高亮与收起动画。
- **音源回退**：在适用的音源或音质错误下，尝试降低音质、跨源匹配和公共流解析。全部失败时提示不可用。

Sonar 没有开屏广告或内置社交页面。歌曲、封面和歌词来自第三方服务，可用性与实际播放音质取决于歌曲和音源；歌单备份保存歌曲信息，不包含音频文件。

## 运行与安装

目前仅分发源码，仓库不提供预编译 App 或 IPA。两端均可从同一个 Xcode 工程构建。

| 平台 | 系统要求 | 运行方式 |
| --- | --- | --- |
| iPhone | iOS 17.0+ | 在 Xcode 中选择 `Sonar`，运行到模拟器或配置个人签名后安装到真机 |
| Mac | macOS 14.0+ | 在 Xcode 中选择 `SonarMac`，或使用下方构建脚本 |

自行打包的 iOS App 可通过适用的个人签名工具安装。TrollStore 仅适用于其支持的系统与设备，请先核对兼容性。

## 从源码构建

需要 Xcode 与命令行工具，以及 **Node.js 18+**。Xcode 版本应包含目标系统所需的 SDK；仓库已提供共享工程和音源资源，不需要本地 Agent 框架。

### 获取源码与构建音源

```sh
git clone https://github.com/can4hou6joeng4/Sonar.git
cd Sonar
npm ci
npm run build:source
```

音源运行时使用 JavaScriptCore。修改 `js-source/` 或音源入口后，应重新执行 `npm run build:source`。

### 运行 iOS App

打开 `Sonar.xcodeproj`，选择 **Sonar** Scheme 和 iPhone 模拟器，点击 Run（`⌘R`）。连接真机时，为 **Sonar** 和 **SonarWidgetExtension** 配置自己的开发团队与签名。

### 运行 Mac App

在同一工程中选择 **SonarMac** 和 **My Mac**，或运行：

```sh
./script/build_and_run.sh --verify
```

脚本会在 `build/macOS/` 生成并本地 ad-hoc 签名 `SonarMac.app`，不需要个人开发者证书。可用 `--debug` 进入 LLDB、`--logs` 查看日志、`--telemetry` 查看播放切换事件。

Mac 启动后显示状态栏图标及已启用的顶部播放器。点击状态栏图标打开选歌面板；播放列表、搜索、顶部播放器开关和歌单备份均在面板内。面板关闭后播放继续，退出按钮在面板右上角。无刘海屏幕使用顶部胶囊。

点击歌曲旁的空心爱心加入个人歌单，再点实心爱心取消收藏。状态栏歌单、搜索结果、当前歌曲与顶部播放器的收藏状态会同步更新。

歌单与搜索结果保留正常滚动并隐藏滚动条，方便直接点击右侧爱心；歌曲行的播放和收藏操作都可直接完成。

取消收藏后，歌曲行会短暂显示“已移除”，再淡出收起；提示带上歌名，便于确认操作结果。

> 直接构建使用仓库中的 `Sonar.xcodeproj`。仅在修改 `project.yml` 并重新生成工程时需要 XcodeGen；App 与 Widget 的构建版本应保持一致。

### 自行打包 IPA

```sh
set -e

xcodebuild -project Sonar.xcodeproj -scheme Sonar \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Sonar.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''

# 在独立临时目录中封装，避免混入之前的 Payload
SONAR_IPA_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sonar-ipa.XXXXXX")"
mkdir -p "$SONAR_IPA_STAGE/Payload"
cp -R build/Sonar.xcarchive/Products/Applications/Sonar.app "$SONAR_IPA_STAGE/Payload/"
(cd "$SONAR_IPA_STAGE" && zip -qr Sonar.ipa Payload)
mv "$SONAR_IPA_STAGE/Sonar.ipa" build/Sonar.ipa
rm -rf "$SONAR_IPA_STAGE"
```

产物为 `build/Sonar.ipa`，未签名，安装前需按设备支持的方式处理。若构建时注入了个人音源凭据，安装包也会包含这些值，请勿公开分发。

## 数据与音源

### 本地资料库

歌单与歌曲元数据保存在本机。iOS 设置中的「歌单备份」和 Mac 面板设置支持 JSON 导入、导出；导入会追加新歌曲并跳过重复项。两端资料库独立，可用备份手动迁移。

Mac 资料库位于 `~/Library/Application Support/cn.bobochang.sonar.mac/Sonar.store`；启用 App Sandbox 签名时位于应用容器对应目录。资料库打开失败时保留原文件，并提供重试与原始资料导出。

### 可选音源凭据

公开源码不包含个人音源凭据。可通过构建环境变量配置相应服务：

| 变量 | 用途 |
| --- | --- |
| `SONAR_WY_TOKEN` | 网易云相关接口的访问凭据 |
| `SONAR_CHKSZ_KEY` | ChKSz 解析接口的访问凭据 |

构建脚本生成 `BuildCredentials.json` 并打包到 App。该文件已被 Git 忽略；使用凭据应遵循相应服务的授权范围和使用条款。

<details>
<summary>播放解析与切歌</summary>

播放解析会从所选音质开始，在适用错误下依次尝试更低音质，再按歌曲标题、歌手和时长寻找另一来源的匹配项，必要时尝试公共流解析。网络错误等情况不会无限重试，可用性仍取决于第三方服务。

Mac 会按当前播放模式提前解析并缓冲下一首。插歌、删歌、排序和模式切换会更新准备目标；音源尚未就绪时仍需等待网络。`--telemetry` 记录解析、媒体就绪和开始播放的阶段耗时，不包含歌曲信息、播放地址或凭据，也不等同于音频输出设备的实测静音间隔。

</details>

## 反馈与参与

欢迎通过 [GitHub Issues](https://github.com/can4hou6joeng4/Sonar/issues) 反馈问题或建议。说明系统版本、触发步骤与实际表现；播放问题可附歌曲名称和来源，截图与日志请先移除凭据和个人信息。

## 免责声明与合规说明

> **请在阅读并理解以下条款后再使用或参与本项目：**

1. **非商业研究用途**：Sonar 为个人兴趣与原生 iOS 架构探索而创建的开源项目，仅用于技术学习、SwiftUI/SwiftData 实践及非商业性研究交流，严禁将本项目及其衍生版本用于任何商业牟利行为。
2. **纯客户端架构与零数据存储**：本项目为纯客户端应用程序，无任何自建后端或中转服务器；本项目不提供音频存储、不分发受版权保护的音视频文件、不持有任何音频媒体数据。播放过程中涉及的音频流、专辑封面与歌词等数据，均由客户端根据用户指令向第三方服务提供方发起公开请求获取。
3. **知识产权归属**：所有由音源返回的歌曲、歌词、专辑图文及商标等合法知识产权均归属于其各自的原始版权方、歌手、唱片公司或对应在线音乐服务平台。
4. **用户义务**：使用者应遵循所在地区的相关法律法规，尊重音乐版权。体验测试完毕后请在 24 小时内自行删除相关解析与缓存文件，支持并购买正版音乐服务。
5. **侵权与异议处理**：若任何版权方或个人认为本项目的开源代码对您的合法权益造成了影响，请通过 GitHub Issue 或电子邮件联系维护者，我们将第一时间积极配合下线或调整相关内容。

## 致谢

感谢 [LINUX DO](https://linux.do/) 为开发者提供分享作品、交流想法的空间，也感谢社区中愿意分享经验与开源实践的佬友。

- [lx-music-mobile](https://github.com/lyswhut/lx-music-mobile)：Sonar 的音源与辅助代码基于其开源实践适配，来源说明保留在源码与许可材料中。
- [Atoll](https://github.com/Ebullioscopic/Atoll)：Mac 顶部播放器的交互参考；Sonar 使用自己的窗口、界面与播放实现，未引入其源代码或素材。

第三方代码、依赖与许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [LICENSES/](LICENSES/)。

## 开源许可证

Sonar 自有代码采用 [GNU General Public License v3.0（GPL-3.0）](LICENSE)。修改与再分发须遵循该许可证；第三方代码保留各自的许可与归属说明。
