# Sonar for Android

Sonar 的 Android 客户端，使用原生 Kotlin、Jetpack Compose 与 AndroidX Media3 构建。它与 iOS/macOS 版共享产品语义：网易云搜索、收藏、歌单、歌词、本地导入与离线缓存，但使用独立的 Android 数据层与播放服务。

## 环境要求

- JDK 17 或更高版本（推荐 JDK 21）
- Android SDK Platform 35、Build-Tools 35.0.0
- Android 8.0（API 26）及以上的设备或模拟器

`android/local.properties` 可以显式指定 SDK：

```properties
sdk.dir=/path/to/android-sdk
```

也可以使用 `ANDROID_HOME` 环境变量。该文件已被忽略，不会进入版本库。

## 构建

```sh
cd android
./gradlew :app:assembleDebug
```

调试包输出到 `app/build/outputs/apk/debug/app-debug.apk`。调试变体的包名带 `.debug` 后缀，可与正式版同时安装。

发布构建：

```sh
./gradlew :app:assembleRelease   # APK
./gradlew :app:bundleRelease     # AAB
```

没有配置签名时，Gradle 仍可生成未签名产物，但无法直接分发。正式发布必须在本地准备签名配置。签名后的产物位于：

- `app/build/outputs/apk/release/app-release.apk`
- `app/build/outputs/bundle/release/app-release.aab`

## 验证

```sh
./gradlew :app:testDebugUnitTest
```

单元测试覆盖 LRC 解析、音质模型与备份编解码。冒烟验证在 Android 15（API 35）模拟器上完成：本地音频导入与后台播放、媒体通知与会话、搜索/歌手/专辑/歌单详情、远程歌单导入、歌单备份导出与再导入、播放队列与音质面板均可用。在线搜索与详情依赖网络；在线播放需要用户自己的网易云 Cookie 或 ChKSz Key，未配置时会在播放页给出可读错误提示。

## 签名

在 `android/keystore.properties` 中填写：

```properties
storeFile=keystore/sonar-release.jks
storePassword=...
keyAlias=sonar
keyPassword=...
```

`storeFile` 相对于 `android/` 解析。首次生成密钥：

```sh
mkdir -p android/keystore
keytool -genkeypair -v \
  -keystore android/keystore/sonar-release.jks \
  -alias sonar \
  -keyalg RSA -keysize 4096 -validity 10000
```

`keystore.properties`、`keystore/` 与所有 `*.jks` 已被忽略。请自行离线备份签名密钥；丢失后无法覆盖安装升级。

## 凭据边界

应用不内置任何账号 Cookie 或第三方 API Key。凭据有两种来源：

1. **运行时配置（推荐）**：设置页 →「账号与音源」。网易云 `MUSIC_U` 与 ChKSz Key 使用 Android Keystore 的 AES-GCM 加密后保存在应用私有目录，不写入日志、备份或导出文件。
2. **构建期注入（可选）**：设置以下环境变量后再构建：

   ```sh
   export SONAR_CHKSZ_KEY="..."
   export SONAR_NETEASE_COOKIE="..."
   export SONAR_WY_TOKEN="..."
   ./gradlew :app:assembleRelease
   ```

   构建脚本会在 `app/build/generated/credentials/build_credentials.json` 生成只读默认凭据。该文件在 `build/` 下并被忽略。公开发布包不应包含个人凭据；建议使用不带环境变量的干净构建。

用户保存的凭据优先于构建期注入值。

## 架构

```text
app/src/main/java/cn/bobochang/sonar/
├── data/
│   ├── cache/       离线音频缓存（当前 + 后续 3 首，1 GB 空间阈值）
│   ├── library/     Room 数据库、收藏/歌单/最近播放、iOS 兼容备份
│   ├── local/       SAF 本地音频导入与内嵌封面提取
│   ├── model/       Track / Quality / MusicSource 等共享模型
│   ├── net/         网易云 legacy API、ChKSz 回退、连通性监测
│   ├── playback/    音质回退、缓存与在线解析
│   └── prefs/       DataStore 设置、Keystore 加密凭据
├── lyrics/          LRC 解析、翻译/音译匹配、30 天缓存
├── playback/        MediaSessionService、MediaController 封装
├── ui/              Compose 界面、主题与 ViewModel
└── di/              手动依赖容器
```

播放链路：

```text
MediaItem(sonar://track/<quality>/<track-json>)
  → ResolvingDataSource
  → 本地文件 / 离线缓存 / 网易云直连 / ChKSz
  → ExoPlayer
```

音质按母带 → Hi-Res → 无损 → 320K → 128K 逐级回退；仅当目标档位不可用时降级，网络或凭据错误会直接报错。播放队列、通知栏与音频焦点由 Media3 `MediaSessionService` 统一管理。

## 数据与备份

- 收藏、个人歌单、最近播放、搜索历史保存在 Room。
- 歌单备份格式与 iOS 的 `sonar.personal-playlist` v1 兼容，可在两端互相导入。
- 离线缓存位于应用私有目录 `files/audio_cache`，清除缓存不会删除收藏、歌单或手动导入的本地音乐。
- 本地导入使用系统文件选择器；应用保存 SAF URI 读取权限。文件被移动、删除或权限被回收后需要重新导入。

## 已知限制

- 在线能力依赖网易云 legacy `/api/` 接口与可选的 ChKSz 第三方服务，接口可能随时变更或限流。
- 登录方式为粘贴 `MUSIC_U` Cookie，暂未提供扫码或手机号登录。
- 暂不支持 Android Auto、Wear OS、Chromecast 与桌面歌词悬浮窗。
- 离线缓存没有单曲下载管理页，按播放队列自动缓存。
- 本地测试源码按仓库约定不纳入版本控制；共享应用可以在没有测试目录的情况下独立构建。

## 分发

发布 APK 时至少提供：

- 已签名的 `app-release.apk` 或 `app-release.aab`
- 版本号与变更说明
- 隐私说明：应用会访问用户配置的第三方账号与网络服务；不收集遥测，不含广告 SDK
- GPL-3.0 许可证与对应源码

上架应用商店前，请自行评估第三方接口、账号使用与内容授权的合规要求。本项目不运营音乐后端，也不随安装包分发音频文件。

## 参考项目

Android 端在架构与交互上参考了以下 GPL-3.0 开源项目，未直接复制其源码：

- [OuterTune](https://github.com/OuterTune/OuterTune)
- [InnerTune](https://github.com/z-huang/InnerTune)
- [Metrolist](https://github.com/mostafaalagamy/Metrolist)
- [Auxio](https://github.com/OxygenCobalt/Auxio)

播放、媒体会话与数据源基于 [AndroidX Media3](https://github.com/androidx/media)。本项目自有代码采用 GPL-3.0。
