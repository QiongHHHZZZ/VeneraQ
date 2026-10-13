import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("debian_build", ROOT / "debian/build.py")
debian = importlib.util.module_from_spec(spec)
spec.loader.exec_module(debian)


class DebianPackageTest(unittest.TestCase):
    def bundle(self, root, arch):
        bundle = root / "bundle"
        (bundle / "lib").mkdir(parents=True)
        (bundle / "data/flutter_assets").mkdir(parents=True)
        header = bytearray(20)
        header[:6] = b"\x7fELF\x02\x01"
        header[18:20] = (62 if arch == "x64" else 183).to_bytes(2, "little")
        (bundle / "venera-next").write_bytes(header)
        (bundle / "lib/libflutter_linux_gtk.so").write_bytes(b"fixture")
        (bundle / "data/icudtl.dat").write_bytes(b"fixture")
        return bundle

    def test_stages_dependencies_architecture_and_existing_install_path(self):
        for arch, expected in debian.DEBIAN_ARCHES.items():
            with self.subTest(arch=arch), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                stage = root / "stage"
                debian.stage_package(self.bundle(root, arch), stage, arch, "1.16.0-rc.1+225")
                control = (stage / "DEBIAN/control").read_text()
                self.assertIn(f"Architecture: {expected}\n", control)
                self.assertIn("Version: 1.16.0~rc.1\n", control)
                self.assertIn("Depends: libwebkit2gtk-4.1-0, libgtk-3-0\n", control)
                self.assertTrue((stage / debian.INSTALL_PATH / "LICENSE").is_file())
                self.assertIn(f"Exec=/{debian.INSTALL_PATH}/venera-next %U",
                              (stage / "usr/share/applications/venera-next.desktop").read_text())

    def test_build_failure_preserves_previous_artifact(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifact = root / "venera-next_1.16.0_amd64.deb"
            artifact.write_bytes(b"previous")
            with patch.object(debian.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "dpkg-deb")):
                with self.assertRaises(subprocess.CalledProcessError):
                    debian.package_bundle(self.bundle(root, "x64"), root, "x64", "1.16.0")
            self.assertEqual(artifact.read_bytes(), b"previous")

    @unittest.skipUnless(shutil.which("dpkg-deb"), "dpkg-deb requires a Linux runner")
    def test_real_deb_roundtrip_for_both_architectures(self):
        for arch, expected in debian.DEBIAN_ARCHES.items():
            with self.subTest(arch=arch), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                package = debian.package_bundle(self.bundle(root, arch), root / "out", arch, "1.16.0+225")
                control = subprocess.check_output(["dpkg-deb", "--field", str(package)], text=True)
                self.assertIn(f"Architecture: {expected}", control)
                self.assertIn("Depends: libwebkit2gtk-4.1-0, libgtk-3-0", control)
                subprocess.run(["dpkg-deb", "--extract", str(package), str(root / "unpacked")], check=True)
                debian.validate_bundle(root / "unpacked" / debian.INSTALL_PATH, arch)
