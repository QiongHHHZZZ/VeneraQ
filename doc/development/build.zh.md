# 构建与开发

本文面向从源码构建、修改 VeneraQ 的开发者。安装和使用说明见仓库根目录的 [README](../../README.md)。

## 项目形态

- VeneraQ 是 Venera-Next 的 fork，**只构建 Android，只产出 release 包**。
- 其他平台的目录（`windows/`、`linux/`、`macos/`、`ios/`、`apple/`、`debian/`、
  `fastlane/`、`patch/`）已删除，对应 CI job 也已移除。
- **没有 `test/` 目录**：测试套件不再随仓库提供，验证靠静态分析与实机验收。

`lib/` 里仍保留着按平台分支的判断（`Platform.isWindows` 等）。它们是兼容代码，安卓运行时
不会走到那些分支；以后要恢复某个平台时，这些分支可以直接复用。

## 环境要求

- Flutter `3.41.4`
- Dart `>=3.8.0 <4.0.0`
- JDK `17`
- Rust 工具链（含 Android targets）
- Android SDK / NDK

```powershell
flutter doctor -v
flutter --version
```

## 获取依赖

```bash
git clone https://github.com/QiongHHHZZZ/VeneraQ.git
cd VeneraQ
flutter pub get --enforce-lockfile
```

不要在不了解影响的情况下删除或重新生成 `pubspec.lock`。Git fork 的来源、固定 commit
和升级要求见[依赖治理](dependencies.zh.md)。

### 联网与代理

有 6 个依赖指向 GitHub（`flutter_qjs`、`flutter.widgets`、`desktop_webview_window`、
`flutter_inappwebview`、`lodepng_flutter`、`flutter_saf`），版本锁在具体 commit 上。

`pub get` 的联网只用于询问“仓库分支有无更新”。网络不好时这一步会长时间挂起，
所以**日常编译一律加 `--no-pub`**，只在改过 `pubspec.yaml` 后联网一次。

需要代理时，只在单条命令里临时设置，不要写进系统配置：

```powershell
cmd /c "set HTTPS_PROXY=http://127.0.0.1:7897&& flutter pub get --enforce-lockfile"
```

### 关键依赖锁定

`rhttp` 必须与 `flutter_rust_bridge 2.11.1` 配套。版本不匹配时构建会成功，但应用启动后
无法联网，日志提示：

```text
flutter_rust_bridge has not been initialized
```

检查锁定版本：

```powershell
Select-String pubspec.lock -Pattern "flutter_rust_bridge" -Context 0,6
```

结果应包含 `version: "2.11.1"`。

## 编译 APK

**一律 release，不碰 debug。**

```powershell
flutter build apk --release --no-pub --target-platform android-arm64
```

- `--target-platform android-arm64`：只编手机需要的架构。
- `--no-pub`：跳过依赖校验，见上文。
- 产物：`build/app/outputs/flutter-apk/app-release.apk`，编译约 12-20 秒。

### 为什么不用 debug

debug 构建代价是 release 的两倍以上，还会让 cargokit 为 `android-x86` 额外编一份
Rust 产物（`packages/rhttp/cargokit/gradle/plugin.gradle` 中
`if (buildType == "debug") platforms.add("android-x86")`），而
`android/app/build.gradle` 的 `abiFilters` 只保留 `armeabi-v7a`、`arm64-v8a`、`x86_64`，
**这份产物永远进不了 APK**。

需要装到设备上验证时，直接安装 release APK。

### 签名

本地 release 签名文件放在：

```text
android/keystore.jks
android/key.properties
```

`android/key.properties` 示例：

```properties
storePassword=你的 store 密码
keyPassword=你的 key 密码
keyAlias=你的 key alias
storeFile=../keystore.jks
```

签名文件和密码属于敏感信息，不得提交到仓库。

## 验证改动

按顺序执行，前两项是 CI 的门禁：

```powershell
flutter analyze --no-pub --fatal-infos --fatal-warnings   # 约 8 秒
python .github/scripts/check_structure_imports.py
python -m unittest discover -s .github/scripts/tests -p "test_*.py"
```

发布相关改动再加：

```powershell
python .github/scripts/release_version.py --check
```

**不要运行 `flutter test`**：`test/` 已不存在，它只会报“没有测试”。

## 磁盘占用

`build/` 只应保留 release 产物与 Rust release 缓存（约 5-6 GB）。下面这些属于永久无用或
可再生的产物，可随时删除：

```text
build/app/intermediates/merged_native_libs/debug
build/app/intermediates/stripped_native_libs/debug
build/app/outputs/flutter-apk/*debug*.apk
build/app/outputs/{apk,mapping,native-debug-symbols}
build/*/build/i686-linux-android
build/*/build/*/debug
```

删掉这几个目录后，`flutter build apk --release --no-pub` 仍能在十几秒内完成。

依赖缓存不在仓库里，位于 `G:\DevCache`（`PUB_CACHE` / `GRADLE_USER_HOME` / `CARGO_HOME`）。
它们在硬盘上，重启不会丢失；删除会使下一次构建重新下载，代价是几十分钟。

## 发布版本

版本号统一维护在 `release.json`：

```json
{
  "version": "2.0.0",
  "build": 1
}
```

发布前更新它，再同步并校验：

```bash
python .github/scripts/release_version.py --write
python .github/scripts/release_version.py --check --tag v2.0.0
```

`pubspec.yaml`、发布 tag 与 `CHANGELOG.md` 的版本章节必须与 `release.json` 一致。

### CI 工作流

| 工作流 | 内容 |
|---|---|
| `代码分析` | 版本与结构检查、Python 脚本测试、修改文件的 Dart 格式检查、`flutter analyze` |
| `依赖安全审查` | 检查 PR 新增或升级的依赖 |
| `PR 平台冒烟构建` | 按改动范围验证 Android 编译 |
| `完整构建` | tag 发布时复用同一质量工作流，再走 `build.yml` |

Android release 需要以下仓库 Secrets：

- `ANDROID_KEYSTORE`：keystore 文件的 Base64 内容
- `ANDROID_KEY_PROPERTIES`：`key.properties` 文本内容

## 问题排查

### 构建成功但应用无法联网

先确认 `flutter_rust_bridge` 仍是 `2.11.1`，且依赖来自本仓库的 `pubspec.lock`。
不要靠盲目升级依赖解决初始化错误。

### 编译长时间停在 `Running "flutter pub get"...`

`pub get` 在联网校验那 6 个 GitHub 依赖。网络不通时它会一直挂着。

处理：中断后改用 `--no-pub` 跳过；需要更新依赖时再用代理联网一次。

### 提示 `Unable to satisfy pubspec.yaml using pubspec.lock`

通常是 Flutter/Dart 版本或包源环境不匹配。核对本页要求的版本与 `flutter doctor -v`
输出，不要直接删锁文件。

### Gradle 下载过慢

可临时切换 Gradle wrapper 镜像或配置网络代理，但**环境相关地址不得提交到仓库**。
提交前确认 `gradle-wrapper.properties` 没混入本地镜像改动。

### 磁盘持续变大

按上文「磁盘占用」一节清理。常见来源是打过 debug 包后留下的
`merged_native_libs/debug` 与各架构的 Rust debug 产物，单个架构可达 1.6 GB。
