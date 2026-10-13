import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "appimage_runtime.py"
spec = importlib.util.spec_from_file_location("appimage_runtime_tested", SCRIPT)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class AppImageRuntimeTest(unittest.TestCase):
    def test_missing_dependency_is_fatal(self):
        with self.assertRaisesRegex(RuntimeError, "libwebkit2gtk"):
            runtime.parse_ldd("libwebkit2gtk-4.1.so.0 => not found\n")

    def test_reads_loader_and_library_paths(self):
        self.assertEqual(runtime.parse_ldd(
            " linux-vdso.so.1 (0x1)\n"
            " libgtk-3.so.0 => /usr/lib/libgtk-3.so.0 (0x2)\n"
            " /lib64/ld-linux-x86-64.so.2 (0x3)\n"
        ), [Path("/usr/lib/libgtk-3.so.0"), Path("/lib64/ld-linux-x86-64.so.2")])
        self.assertEqual(runtime.parse_ldd(
            "libgtk-3.so.0 => /tmp/app with spaces/usr/lib/libgtk-3.so.0 (0x123)\n"
        ), [Path("/tmp/app with spaces/usr/lib/libgtk-3.so.0")])

    def test_only_host_abi_and_drivers_are_excluded(self):
        for name in ("libc.so.6", "libm.so.6", "ld-linux-aarch64.so.1", "libEGL.so.1", "libdrm.so.2"):
            self.assertIsNotNone(runtime.HOST_LIBRARIES.fullmatch(name), name)
        for name in ("libwebkit2gtk-4.1.so.0", "libgtk-3.so.0", "libstdc++.so.6", "libgio-2.0.so.0", "libcrypto.so.3"):
            self.assertIsNone(runtime.HOST_LIBRARIES.fullmatch(name), name)

    def test_validation_rejects_unbundled_system_library(self):
        with tempfile.TemporaryDirectory() as temp:
            appdir = Path(temp)
            (appdir / "app").write_bytes(b"\x7fELF")
            with patch.object(runtime, "dependencies", return_value=[Path("/usr/lib/libwebkit2gtk-4.1.so.0")]):
                with self.assertRaisesRegex(RuntimeError, "still requires host"):
                    runtime.validate_runtime(appdir)

    def test_validation_allows_bundled_library_and_glibc(self):
        with tempfile.TemporaryDirectory() as temp:
            appdir = Path(temp).resolve()
            (appdir / "app").write_bytes(b"\x7fELF")
            with patch.object(runtime, "dependencies", return_value=[appdir / "usr/lib/libgtk-3.so.0", Path("/lib/libc.so.6")]):
                runtime.validate_runtime(appdir)

    def test_runtime_paths_relocate_without_disabling_sandbox(self):
        environment = runtime.runtime_environment("aarch64-linux-gnu")
        self.assertIn('$APPDIR/usr/lib/aarch64-linux-gnu/webkit2gtk-4.1', environment)
        self.assertIn("GIO_MODULE_DIR", environment)
        self.assertIn("GDK_PIXBUF_MODULE_FILE", environment)
        self.assertNotIn("DISABLE_SANDBOX", environment)
        self.assertNotIn("/workspace", environment)


if __name__ == "__main__":
    unittest.main()
