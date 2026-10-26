<div align="center">

# VeneraQ

![Flutter](https://img.shields.io/badge/Flutter-3.41.4-02569B?logo=flutter&logoColor=white&style=flat-square)
[![Release](https://img.shields.io/github/v/release/VeneraQ/VeneraQ?label=Release&color=10B981&style=flat-square)](https://github.com/VeneraQ/VeneraQ/releases/latest)
![License](https://img.shields.io/badge/License-GPL--3.0-10B981?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white&style=flat-square)

一个 Android 漫画阅读器。基于 [Venera](https://github.com/venera-app/venera) 重写，仅支持 Android。

</div>

---

## 下载

从 [Releases](https://github.com/VeneraQ/VeneraQ/releases/latest) 安装 APK：

- `VeneraQ-xxx-android.apk` — 通用版，推荐
- 另有 ARM64 / ARM32 / x86_64 单独版本

## 功能

- **阅读** — 纵向连续、横向翻页，章尾自动接下章；夜间调光
- **书架** — 列表与网格两种排布，可排序、筛选、跨文件夹移动
- **本地漫画** — 下载的章节存入本地库，可离线阅读、移动、删除
- **离线** — 整本或按章节下载
- **数据** — 本地导出/导入，支持 Pica 数据迁移
- **漫画源** — 加载用户自备的 JS 源，脚本运行在独立引擎中

## 上手

1. 安装 APK
2. 选内容来源：本地导入，或添加 JS 漫画源
3. 详情页点阅读，章节列表可长按多选批量标记
4. 想离线看就下载章节

## 开发

- 构建说明：[doc/development/build.zh.md](doc/development/build.zh.md)
- 文档索引：[doc/README.md](doc/README.md)
- 漫画源编写：[doc/api/comic_source.zh.md](doc/api/comic_source.zh.md)
- 更新日志：[CHANGELOG.md](CHANGELOG.md)

## 声明

本仓库只维护阅读器本体，**不提供、内置、托管或推荐任何漫画源**，需用户自行配置。请勿提交与漫画源、源站内容或版权相关的问题。

## 许可

GPL-3.0。
