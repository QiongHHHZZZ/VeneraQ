# AVIF 候选库独立探测

固定 `libavif 0.1.1` 和 Dart 依赖锁，用于评估静态／动画解码、无效输入、输入大小上限、取消后恢复。此目录保存工程模板，避免要求主应用升级其固定的 Flutter / Dart SDK。原始结果与接入限制见 [评估文档](../../doc/experiments/avif_decoder.zh.md)。

在独立目录中使用 Dart >=3.12（本轮为 3.13.5）。构建工具需要 Rust 1.92、CMake、Meson、Ninja；x64 还需要 NASM，以及对应平台的 C/C++ 编译器。工具必须可由构建进程的 PATH 找到。

```powershell
# 在仓库根目录执行；使用一个尚不存在的临时目录。
$probe = 'D:/avif-probe'
$dart = '<独立 Dart SDK>/bin/dart.exe'
$fixtures = (Resolve-Path test/fixtures/avif).Path
New-Item -ItemType Directory -Path "$probe/bin" | Out-Null
Copy-Item tool/avif_candidate_probe/pubspec.yaml.template "$probe/pubspec.yaml"
Copy-Item tool/avif_candidate_probe/probe.dart.template "$probe/bin/probe.dart"
Copy-Item tool/avif_candidate_probe/pubspec.lock "$probe/pubspec.lock"
Copy-Item tool/avif_candidate_probe/analysis_options.yaml "$probe/analysis_options.yaml"
$env:PUB_HOSTED_URL = 'https://pub.dev'
Push-Location $probe
try {
  & $dart pub get --enforce-lockfile
  & $dart analyze
  & $dart run bin/probe.dart $fixtures
} finally { Pop-Location }
```

上面的流程使用原版包。本轮 Windows 原版构建受到 native-assets 深层目录与 MSVC 路径限制影响；成功解码结果来自另外一份实验副本，不能据此声称原版 Windows 包可直接接入。

`windows_build_experiment.patch` 记录当次对源码副本的构建调整：Ninja、短 CMake 输出目录，以及把 MSVC 格式的 `libdav1d.a` 复制为 Rust 构建脚本期望的 `dav1d.lib`。它含当次临时目录，复现时必须调整该路径；只用于隔离副本，不修改全局 Pub 缓存。副本的 `pubspec.yaml` 需去掉 `resolution: workspace`，探测工程通过 `pubspec_overrides.yaml` 的 `dependency_overrides.libavif.path` 指向它。成功结果不包含对解码算法或 Dart 接口的修改。

程序逐行输出 JSON，`supported: false` 是兼容性结果。无效输入意外成功、像素／帧数不一致、取消无法收尾等异常会导致非零退出。每次异步调用有 10 秒期限；自动化运行还应设置外层进程期限，因为 Dart 超时不能中断卡住的原生线程。帧缓冲区的长期内存回收、Flutter 图片流接入及其他平台仍需单独验证。
