# Disk logs

中文：[磁盘日志](logging.zh.md)

The application writes `info`, `warning`, `error`, and extension logs to `logs.txt`. The level filter in the log page affects only that page. JavaScript extension `console.log` entries use the same persistence path.

On Windows, macOS, and Linux, the file lives in the application data directory (`App.dataPath`). On Windows this is normally `%APPDATA%\com.github.cyrilpeng\VeneraNext\logs.txt`; use the actual application directory after customization or migration. Android uses the application's external storage directory, falling back to its data directory, and iOS uses its data directory. Development code can read the exact active path from `Log.filePath`.

Logging starts after the core acquires ownership of the data directory. The last 500 entries collected before startup are replayed once. Existing logs survive restarts. Each asynchronous batch appends, flushes, and closes the file, allowing direct inspection with an editor or PowerShell:

```powershell
Get-Content -LiteralPath "$env:APPDATA\com.github.cyrilpeng\VeneraNext\logs.txt" -Tail 100 -Wait
```

Before a batch would exceed approximately 2 MiB, the file rotates to `logs.previous.txt`. Only the current file and one previous file are retained; a single oversized record is written in full. If storage is temporarily unavailable, a console diagnostic is emitted and up to 500 pending records are retained for retry on the next addition or flush. Normal shutdown and log export wait for current writes. Forced termination can lose records that have not reached disk.

Content is limited to 3,000 characters per entry by default. Choose **Disable Length Limitation** in Settings → Logs to capture full responses for the current run; it applies to both page and disk contents. The page retains up to 500 records, while disk files may contain older entries. Clear and Export operate on the in-memory records; Clear does not remove disk history.

Headless commands preserve their existing muted logging policy to keep machine protocol output stable.
