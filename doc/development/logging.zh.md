# 磁盘日志

English: [Disk logs](logging.en.md)

应用将 `info`、`warning`、`error` 和扩展的日志统一写入 `logs.txt`。设置中的日志级别筛选只影响页面显示，磁盘文件不按级别过滤。JavaScript 扩展的 `console.log` 通过同一日志入口保存。

Windows、macOS 和 Linux 的文件位于应用数据目录（`App.dataPath`）中。Windows 通常是 `%APPDATA%\com.github.cyrilpeng\VeneraNext\logs.txt`，自定义／迁移后的路径以应用实际数据目录为准。Android 使用应用外部存储目录，无法取得时使用应用数据目录；iOS 使用应用数据目录。当前会话的确切路径可由开发代码读取 `Log.filePath`。

日志从应用取得数据目录所有权后开始追加，启动早期内存中的最后 500 条日志补写一次。重启不会覆盖旧日志。写入按批次异步执行，每批都会刷新并关闭文件，因此可直接用编辑器查看，或在 PowerShell 中跟踪：

```powershell
Get-Content -LiteralPath "$env:APPDATA\com.github.cyrilpeng\VeneraNext\logs.txt" -Tail 100 -Wait
```

文件达到约 2 MiB 时，在下一批写入前轮转为 `logs.previous.txt`，只保留当前文件和上一份文件；单条日志超过阈值时仍完整写入。磁盘暂时不可写时向控制台报告错误，保留最多 500 条待写记录，并在后续日志／刷新时重试。应用正常退出和日志导出都会等待当前写入完成；进程被强行终止时，尚未写入的记录可能丢失。

单条内容默认最多 3,000 个字符。需要完整响应体时，在「设置 → 日志」中选择「禁用长度限制」，该选择仅在本次运行有效，同时作用于页面和磁盘内容。页面最多保存 500 条记录，磁盘轮转文件可包含更早记录。页面的「清空」和「导出」操作针对内存记录，清空不会删除磁盘历史。

无头命令模式沿用静默日志策略，不主动输出或记录应用日志，以保持机器协议输出稳定。
