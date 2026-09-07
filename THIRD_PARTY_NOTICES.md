# 第三方代码与许可说明

本文件记录 Sonar 使用的第三方代码及相应许可文本。下列许可证仅覆盖对应的第三方内容，**不构成对 Sonar 自有代码的整体许可证选择**。核对日期：2026-09-07。

## 音源实现

| 来源 | 使用范围 | 许可材料 |
| --- | --- | --- |
| [lx-music-mobile](https://github.com/lyswhut/lx-music-mobile) | `js-source/` 中保留并适配的音源与辅助代码，以及生成 bundle 中的对应内容 | [Apache License 2.0](LICENSES/lx-music-mobile.txt) |
| [NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi) / Binaryify | 网易模块中标注的歌曲详情、歌单、歌词和加密实现参考；来源链接保留在对应源码中 | [MIT，Copyright (c) 2013–2022 Binaryify](LICENSES/NeteaseCloudMusicApi.txt) |

`js-source/` 是为 Sonar 修改的分发版本，不能视为未经修改的上游发布版。适配包括 JavaScriptCore 宿主桥接、仅保留网易与 QQ 路径，以及搜索、歌手和专辑等入口调整。文件中的原有来源说明保留，并增加了修改版本标记。

lx-music-mobile 的许可文件来自其上游仓库；核对时根目录没有独立 NOTICE 文件。NeteaseCloudMusicApi 当前归档仓库仅保留说明文件，因此使用其原始 npm 包 `NeteaseCloudMusicApi@4.28.0` 中的 LICENSE 核对 MIT 文本，下载内容已通过发布元数据的 SHA-512 校验。这里的版本用于追溯许可文本，**不表示 Sonar 的全部适配代码准确源自该版本**。

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

## 源码保留的其他参考链接（公开发布前待核实）

下列引用由适配源码保留。它们并不自动由 lx-music-mobile 的整体许可覆盖；在未确认实际采用的回答版本及授权条件前，不将本清单视为完整的公开分发许可结论。

| 本地函数 | 引用与作者 | 当前核对状态 |
| --- | --- | --- |
| `compareVer` | [Stack Overflow 53387532](https://stackoverflow.com/a/53387532)，[vanowm](https://stackoverflow.com/users/2930038/vanowm) | API 当前页面标注 CC BY-SA 4.0；采用的历史版本尚未确定 |
| `arrShuffle` | [Stack Overflow 2450976](https://stackoverflow.com/a/2450976)，[ChristopheD](https://stackoverflow.com/users/81179/christophed) | API 当前页面标注 CC BY-SA 4.0；采用的历史版本尚未确定 |
| `blobToBuffer` | [Stack Overflow 64945178](https://stackoverflow.com/a/64945178)，[Chris Rice](https://stackoverflow.com/users/1148118/chris-rice) | API 当前页面标注 CC BY-SA 4.0；采用的历史版本尚未确定 |
| `sizeFormate` | [Gist 3511330](https://gist.github.com/thomseddon/3511330)，thomseddon | 已核对公开 Gist 文件列表，未发现单独的许可证文件；许可尚未确认 |
| `similar` | [CSDN 77164126](https://blog.csdn.net/xcxy2015/article/details/77164126)，链接账号 xcxy2015 | 来源链接仍在代码中，许可尚未确认 |

[CC BY-SA 4.0 参考文本](LICENSES/cc-by-sa-4.0.txt) 从 GitHub 许可证 API 保存；当前页面许可不等于对历史导入版本或整个 Sonar 项目的重新授权。发布前需核对相关版本与条件，或另行处理这些片段。

## 分发与维护

- `LICENSES/` 保存上述许可正文，[sources.json](LICENSES/sources.json) 记录来源、版本与校验信息。
- `npm run build:source` 将归属说明与许可正文写入 `source-bundle.js` 的注释头，并保留依赖中可识别的许可注释；该资源随 App 一起打包。
- 更新依赖或增减第三方源码时，应重新核对版本、适用许可和归属信息，而不是沿用旧清单。
- 对第三方许可的整理不等同于对音乐内容、服务接口或商标取得授权，也不替代对 Sonar 自有代码许可证的明确选择。
