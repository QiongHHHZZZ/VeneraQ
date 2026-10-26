# 文档索引

本文档是 `doc/` 目录的入口。新增文档时按类型放入子目录，统一使用 `topic.zh.md` 命名。

## 目录约定

| 目录 | 类型 |
|---|---|
| `api/` | 开发 API、扩展接口、脚本接口 |
| `architecture/` | 结构评估、依赖清单 |
| `examples/` | 配套代码模板 |
| `development/` | 本地开发、构建和开发故障排查 |
| `user/` | 用户使用说明、导入格式、命令行用法 |
| `experiments/` | 实验设计、任务跟踪、技术预研；不作为正式路线图承诺 |

## 开发 API

第三方源开发者建议按“[编写指南](api/comic_source.zh.md) → [最小模板](examples/minimal_source.js) → [API 参考](api/js.zh.md) → [本地调试](development/source_debugging.zh.md) → [发布脚本与源仓库](api/comic_source.zh.md#7-发布脚本与源仓库)”阅读。

- [漫画源开发说明](api/comic_source.zh.md)
- [JavaScript API](api/js.zh.md)

## 开发和构建

- [构建与开发](development/build.zh.md)
- [漫画源本地调试](development/source_debugging.zh.md)
- [磁盘日志](development/logging.zh.md)
- [依赖治理](development/dependencies.zh.md)
- [图标替换](development/app-icon.zh.md)

## 用户和命令行

- [漫画源与源仓库](user/source_repositories.zh.md)
- [无头命令模式](user/headless.zh.md)

## 实验和任务跟踪

- [漫画源安装任务交互设计](experiments/source_installation_tasks.zh.md)
- [漫画源与源仓库管理设计](experiments/source_repositories.zh.md)
- [图片增强实验](experiments/image_enhancement.zh.md)
- [去混淆像素复制优化](experiments/image_descrambling.zh.md)
- [AVIF 格式识别与解码评估](experiments/avif_decoder.zh.md)

## 维护原则

- README 只保留用户最需要的入口，不承载长篇开发文档。
- 文档统一使用中文，文件名以 `.zh.md` 结尾。
- `experiments/` 文档用于记录判断、风险和任务，不在功能稳定前写进 README 的功能宣传。
- 源相关文档只描述扩展接口和运行时契约，不提供、推荐、维护或验证任何第三方漫画源。
