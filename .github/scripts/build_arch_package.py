import argparse
import re
import shutil
import subprocess
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PUBSPEC_PATH = ROOT / "pubspec.yaml"
BUILD_LINUX_DIR = ROOT / "build" / "linux"
BUNDLE_DIR = BUILD_LINUX_DIR / "x64" / "release" / "bundle"
APP_DIR = BUILD_LINUX_DIR / "app"
ARCH_DIR = BUILD_LINUX_DIR / "arch"


class ArchBuildError(RuntimeError):
    pass


def _clean_value(value: str) -> str:
    value = value.strip()
    if "#" in value:
        value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def _top_level_value(text: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:\s*(?P<value>.+?)\s*$", text, re.MULTILINE)
    if not match:
        raise ArchBuildError(f"pubspec.yaml does not contain {key}")
    return _clean_value(match.group("value"))


def _flutter_to_arch_config(text: str) -> dict[str, object]:
    lines = text.splitlines()
    config: dict[str, object] = {}
    in_block = False
    current_list: str | None = None

    for line in lines:
        if not in_block:
            if line.strip() == "flutter_to_arch:":
                in_block = True
            continue

        if line.strip() and not line.startswith((" ", "\t")):
            break

        field = re.match(r"\s{2}([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if field:
            key = field.group(1)
            value = _clean_value(field.group(2))
            if value:
                config[key] = value
                current_list = None
            else:
                config[key] = []
                current_list = key
            continue

        item = re.match(r"\s{4}-\s*(.+?)\s*$", line)
        if item and current_list:
            values = config[current_list]
            if not isinstance(values, list):
                raise ArchBuildError(f"flutter_to_arch.{current_list} is not a list")
            values.append(_clean_value(item.group(1)))

    if not config:
        raise ArchBuildError("pubspec.yaml does not contain flutter_to_arch config")
    return config


def _required_string(config: dict[str, object], key: str) -> str:
    value = config.get(key)
    if not isinstance(value, str) or not value:
        raise ArchBuildError(f"flutter_to_arch.{key} is required")
    return value


def _required_list(config: dict[str, object], key: str) -> list[str]:
    value = config.get(key)
    if not isinstance(value, list) or not value or not all(isinstance(i, str) for i in value):
        raise ArchBuildError(f"flutter_to_arch.{key} must be a non-empty list")
    return value


def _arch_version(pubspec_version: str) -> tuple[str, str]:
    version, separator, build = pubspec_version.partition("+")
    if not separator:
        build = "1"
    return version.replace("-", "_"), build


def _desktop_file(
    display_name: str,
    description: str,
    package_name: str,
    categories: str,
    keywords: str,
) -> str:
    return f"""[Desktop Entry]
Name={display_name}
GenericName={display_name}
Comment={description}
Terminal=false
Type=Application
Categories={categories}
Exec=/usr/bin/{package_name}_pkg/{package_name}
Keywords={keywords}
Icon={package_name}
""".strip()


def _pkgbuild(
    package_name: str,
    description: str,
    version: str,
    build: str,
    url: str,
    depends: list[str],
) -> str:
    depends_value = " ".join(f"'{dependency}'" for dependency in depends)
    return f"""pkgname={package_name}
pkgver={version}
pkgrel={build}
pkgdesc="{description}"
arch=('x86_64')
source=("app.tar.gz")
md5sums=('SKIP')
url="{url}"
depends=({depends_value})

package() {{
    cd "$srcdir"
    install -Dm755 app/{package_name} "$pkgdir/usr/bin/{package_name}_pkg/{package_name}"
    install -d "$pkgdir/usr/bin/{package_name}_pkg/lib"
    cp -r app/lib/* "$pkgdir/usr/bin/{package_name}_pkg/lib/"
    install -d "$pkgdir/usr/bin/{package_name}_pkg/data"
    cp -r app/data/* "$pkgdir/usr/bin/{package_name}_pkg/data/"
    install -Dm644 app/icon.png "$pkgdir/usr/share/icons/hicolor/64x64/apps/{package_name}.png"
    install -Dm644 app/app.desktop "$pkgdir/usr/share/applications/$pkgname.desktop"
    ln -s "/usr/bin/{package_name}_pkg/{package_name}" "$pkgdir/usr/bin/{package_name}"
}}
""".strip()


def _dockerfile(package_name: str, version: str, build: str, depends: list[str]) -> str:
    depends_value = " ".join(depends)
    return f"""FROM archlinux:latest

RUN pacman -Syu --noconfirm base-devel

RUN pacman -Syu --noconfirm {depends_value} sudo

RUN useradd -m user

RUN passwd -d user

WORKDIR /home/user

CMD cp -r /build/* /home/user/ && sudo -u user makepkg -s --noconfirm && rm -f app.tar.gz PKGBUILD Dockerfile && cp -r ./* /build/
""".strip()


def _run(command: list[str], cwd: Path) -> None:
    print(f"+ {' '.join(command)}")
    subprocess.run(command, cwd=cwd, check=True)


def _is_arch_linux() -> bool:
    return Path("/etc/arch-release").exists() and shutil.which("makepkg") is not None


def _make_app_archive(package_name: str, icon_path: str, desktop_content: str) -> None:
    executable = BUNDLE_DIR / package_name
    if not executable.exists():
        available = ", ".join(path.name for path in sorted(BUNDLE_DIR.iterdir())) if BUNDLE_DIR.exists() else "none"
        raise ArchBuildError(
            f"Expected Linux executable {executable}, but it was not found. "
            f"Available bundle entries: {available}"
        )

    icon = ROOT / icon_path
    if not icon.exists():
        raise ArchBuildError(f"Icon file {icon} does not exist")

    if APP_DIR.exists():
        shutil.rmtree(APP_DIR)
    shutil.copytree(BUNDLE_DIR, APP_DIR)
    shutil.copyfile(icon, APP_DIR / "icon.png")
    (APP_DIR / "app.desktop").write_text(desktop_content, encoding="utf-8")

    archive = BUILD_LINUX_DIR / "app.tar.gz"
    if archive.exists():
        archive.unlink()
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(APP_DIR, arcname="app")
    shutil.rmtree(APP_DIR)

    if ARCH_DIR.exists():
        shutil.rmtree(ARCH_DIR)
    ARCH_DIR.mkdir(parents=True)
    shutil.move(str(archive), ARCH_DIR / "app.tar.gz")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="write Arch packaging inputs without running makepkg or Docker",
    )
    args = parser.parse_args()

    text = PUBSPEC_PATH.read_text(encoding="utf-8")
    config = _flutter_to_arch_config(text)
    package_name = _required_string(config, "name")
    description = _top_level_value(text, "description")
    version, build = _arch_version(_top_level_value(text, "version"))
    icon = _required_string(config, "icon")
    categories = _required_string(config, "categories")
    keywords = _required_string(config, "keywords")
    url = _required_string(config, "url")
    depends = _required_list(config, "depends")

    desktop_content = _desktop_file(
        display_name="VeneraNext",
        description=description,
        package_name=package_name,
        categories=categories,
        keywords=keywords,
    )
    _make_app_archive(package_name, icon, desktop_content)
    (ARCH_DIR / "PKGBUILD").write_text(
        _pkgbuild(package_name, description, version, build, url, depends),
        encoding="utf-8",
    )
    (ARCH_DIR / "Dockerfile").write_text(
        _dockerfile(package_name, version, build, depends),
        encoding="utf-8",
    )

    if args.prepare_only:
        print(f"Prepared build/linux/arch for {package_name}-{version}-{build}")
        return

    if _is_arch_linux():
        _run(["makepkg", "-s", "--noconfirm"], ARCH_DIR)
    else:
        _run(["docker", "build", "-t", "archpkg-builder", "."], ARCH_DIR)
        mount = f"type=bind,source={ARCH_DIR.resolve()},target=/build"
        _run(["docker", "run", "--rm", "--mount", mount, "archpkg-builder"], ARCH_DIR)

    print(f"build/linux/arch/{package_name}-{version}-{build}-x86_64.pkg.tar.zst")


if __name__ == "__main__":
    try:
        main()
    except ArchBuildError as error:
        print(f"::error::{error}")
        raise SystemExit(1)
