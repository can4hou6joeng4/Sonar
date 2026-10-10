# 第三方代码与许可说明

本文件记录 Sonar 使用的第三方代码及相应许可文本。下列许可证仅覆盖对应的第三方内容；Sonar 自有代码采用根目录的 GPL-3.0 许可证。核对日期：2026-10-06。

## 音源实现

| 来源 | 使用范围 | 许可材料 |
| --- | --- | --- |
| [lx-music-mobile](https://github.com/lyswhut/lx-music-mobile) | `js-source/` 中保留并适配的音源与辅助代码，以及生成 bundle 中的对应内容 | [Apache License 2.0](LICENSES/lx-music-mobile.txt) |

`js-source/` 是为 Sonar 修改的分发版本，不能视为未经修改的上游发布版。适配包括 JavaScriptCore 宿主桥接、仅保留 QQ 音乐路径，以及搜索、歌手和专辑等入口调整。文件中的原有来源说明保留，并增加了修改版本标记。

lx-music-mobile 的许可文件来自其上游仓库；核对时根目录没有独立 NOTICE 文件。

网易适配器及其参考的 [NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) 实现已从当前分发代码中移除。[MIT 许可文本](LICENSES/NeteaseCloudMusicApi.txt)和 `LICENSES/sources.json` 中的原始核对记录仍保留，用于追溯历史版本。

当前网易云歌曲搜索、歌词和播放通过 Sonar 的 Swift 适配器请求 ChKSz API，未恢复上述 JavaScript 网易客户端实现。

## npm 依赖

版本对应本仓库 `package-lock.json`。许可文本保留包内原文及版权说明。

| 依赖 | 版本 | 用途 | 许可文本 |
| --- | --- | --- | --- |
| base64-js | 1.5.1 | bundle 运行时 | [MIT](LICENSES/base64-js.txt) |
| buffer | 6.0.3 | bundle 运行时 | [MIT](LICENSES/buffer.txt) |
| ieee754 | 1.2.1 | bundle 运行时 | [BSD-3-Clause](LICENSES/ieee754.txt) |
| he | 1.2.0 | bundle 运行时 | [MIT](LICENSES/he.txt) |
| pako | 2.2.0 | bundle 运行时 | [MIT](LICENSES/pako.txt) 与 [zlib 源码声明](LICENSES/pako-zlib.txt) |
| esbuild | 0.28.2 | 构建工具 | [MIT](LICENSES/esbuild.txt) |
| lrc-file-parser | 1.2.7 | 已声明的开发依赖，当前 bundle 中未检测到对应模块 | [MIT](LICENSES/lrc-file-parser.txt) |

## 已处理的历史辅助代码引用

2026-10-06 清理了以下辅助片段。三项未被 Sonar 音源入口调用的函数已移除；两项仍使用的功能已由 Sonar 重新实现。历史来源继续记录在此和 `LICENSES/sources.json`，不将它们归入 lx-music-mobile 的整体许可，也不宣称已取得原片段的额外授权。

| 功能 | 历史引用与作者 | 当前分发版本的处理 |
| --- | --- | --- |
| `compareVer` | [Stack Overflow 53387532](https://stackoverflow.com/a/53387532)，[vanowm](https://stackoverflow.com/users/2930038/vanowm) | 未使用，已移除 |
| `arrShuffle` | [Stack Overflow 2450976](https://stackoverflow.com/a/2450976)，[ChristopheD](https://stackoverflow.com/users/81179/christophed) | 未使用，已移除；App 播放队列使用 Swift 实现 |
| `blobToBuffer` | [Stack Overflow 64945178](https://stackoverflow.com/a/64945178)，[Chris Rice](https://stackoverflow.com/users/1148118/chris-rice) | 移除原数据 URL/base64 片段，改用原始 ArrayBuffer 字节读取 |
| `sizeFormate` | [Gist 3511330](https://gist.github.com/thomseddon/3511330)，thomseddon | 移除原片段，改用逐级单位换算，保留音源 SDK 的显示格式 |
| `similar` | [CSDN 77164126](https://blog.csdn.net/xcxy2015/article/details/77164126)，链接账号 xcxy2015 | 未使用，已移除 |

`LICENSES/cc-by-sa-4.0.txt` 仅保留为历史核对材料，不再作为当前音源 bundle 的依赖许可拼入。此次处理针对当前分发版本，不改变旧提交的源码或许可情况，也不是对整个 Git 历史的许可审计结论。

## 分发与维护

- `LICENSES/` 保存上述许可正文，[sources.json](LICENSES/sources.json) 记录来源、版本与校验信息。
- `npm run build:source` 将归属说明与许可正文写入 `source-bundle.js` 的注释头，并保留依赖中可识别的许可注释；该资源随 App 一起打包。
- 更新依赖或增减第三方源码时，应重新核对版本、适用许可和归属信息，而不是沿用旧清单。
- 对第三方许可的整理不等同于对音乐内容、服务接口或商标取得授权，也不替代对 Sonar 自有代码许可证的明确选择。
