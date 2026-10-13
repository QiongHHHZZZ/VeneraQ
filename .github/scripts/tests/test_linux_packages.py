import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "build_linux_packages.py"
spec = importlib.util.spec_from_file_location("linux_packages", SCRIPT)
packages = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packages)


class LinuxPackagesTest(unittest.TestCase):
    def make_bundle(self, root, machine=62):
        bundle = root / "bundle"
        (bundle / "lib").mkdir(parents=True)
        (bundle / "data/flutter_assets").mkdir(parents=True)
        header = bytearray(20)
        header[:6] = b"\x7fELF\x02\x01"
        header[18:20] = machine.to_bytes(2, "little")
        (bundle / "venera-next").write_bytes(header)
        (bundle / "lib/libflutter_linux_gtk.so").write_bytes(b"flutter")
        (bundle / "data/icudtl.dat").write_bytes(b"icu")
        (bundle / "data/flutter_assets/test.txt").write_text("asset")
        return bundle

    def test_rejects_wrong_architecture_and_incomplete_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            bundle = self.make_bundle(Path(temp))
            packages.validate_bundle(bundle, "x64")
            with self.assertRaises(ValueError):
                packages.validate_bundle(bundle, "arm64")
            (bundle / "data/icudtl.dat").unlink()
            with self.assertRaisesRegex(ValueError, "icudtl.dat"):
                packages.validate_bundle(bundle, "x64")

    def test_stages_all_flutter_assets_and_launcher(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bundle = self.make_bundle(root, 183)
            appdir = root / "app with spaces.AppDir"
            packages.stage_appdir(bundle, appdir)
            packages.validate_bundle(appdir / "usr/lib/venera-next", "arm64")
            self.assertEqual((appdir / "usr/lib/venera-next/data/flutter_assets/test.txt").read_text(), "asset")
            self.assertTrue((appdir / "usr/lib/venera-next/LICENSE").is_file())
            self.assertNotIn(b"\r", (appdir / "AppRun").read_bytes())
            self.assertIn('"$@"', (appdir / "AppRun").read_text())
            self.assertIn("Exec=AppRun %U", (appdir / "venera-next.desktop").read_text())

    def test_versions_preserve_build_and_prerelease_order(self):
        self.assertEqual(packages.versions("1.16.0+225"), ("1.16.0", "225"))
        self.assertEqual(packages.versions("1.17.0-beta.2+226"), ("1.17.0~beta.2", "226"))
        self.assertEqual(packages.versions("1.17.0"), ("1.17.0", "1"))
        with self.assertRaises(ValueError):
            packages.versions("1.17.0\n%post")

    def test_rpm_filters_only_bundled_library_requirements(self):
        content = packages.rpm_spec("1.16.0", "225", {"libflutter_linux_gtk.so", "librhttp.so"})
        expression = re.search(r"^%global __requires_exclude (.+)$", content, re.M).group(1)
        self.assertRegex("librhttp.so()(64bit)", expression)
        self.assertRegex("libflutter_linux_gtk.so()(64bit)", expression)
        self.assertNotRegex("libgtk-3.so.0()(64bit)", expression)
        self.assertNotRegex("libc.so.6(GLIBC_2.35)(64bit)", expression)

    def test_rejects_download_checksum_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "tool"
            path.write_bytes(b"corrupt")
            with self.assertRaisesRegex(RuntimeError, "SHA256"):
                packages.download_verified("https://example.invalid/tool", path, "0" * 64)
            self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
