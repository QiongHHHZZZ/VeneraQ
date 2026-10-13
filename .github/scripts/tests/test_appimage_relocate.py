from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == "linux" and shutil.which("cc"), "Requires a Linux C compiler")
class WebKitRelocationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.binary = cls.root / "relocate"
        source = Path(__file__).resolve().parents[1] / "appimage_relocate.c"
        subprocess.run(["cc", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_relocation_preserves_elf_offsets_and_path_suffixes(self):
        old = b"/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1"
        original = b"\x7fELF\0" + old + b"\0" + old + b"/injected-bundle/\0/usr/bin/bwrap\0/usr/bin/xdg-dbus-proxy\0TAIL"
        source, target = self.root / "original", self.root / "relocated"
        source.write_bytes(original)
        subprocess.run([str(self.binary), str(source), str(target), old.decode(), "/tmp/v123456"], check=True)
        result = target.read_bytes()
        self.assertEqual(len(result), len(original))
        self.assertEqual(result[-4:], b"TAIL")
        self.assertIn(b"/tmp/v123456/w/injected-bundle/\0", result)
        self.assertIn(b"/tmp/v123456/b\0", result)
        self.assertIn(b"/tmp/v123456/d\0", result)
        self.assertEqual(source.read_bytes(), original)

    def test_unknown_webkit_layout_fails_without_publishing_copy(self):
        source, target = self.root / "unknown", self.root / "rejected"
        source.write_bytes(b"\x7fELF\0unexpected library layout\0")
        result = subprocess.run([str(self.binary), str(source), str(target), "/usr/lib/webkit", "/tmp/v123456"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
