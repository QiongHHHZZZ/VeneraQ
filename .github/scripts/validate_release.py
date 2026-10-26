import argparse
import os
import re
import sys
from pathlib import Path

from release_version import ReleaseVersionError, check_release_files


def fail(message: str) -> None:
    print(f"::error::{message}")
    raise SystemExit(1)


def read_text(path: str) -> str:
    return Path(path).read_text(encoding="utf-8")


def extract_release_notes(tag: str) -> str:
    text = read_text("CHANGELOG.md")
    pattern = (
        rf"^##[^\S\r\n]+{re.escape(tag)}[^\S\r\n]*$\n"
        r"(?P<body>.*?)(?=^##[^\S\r\n]+|\Z)"
    )
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if not match:
        fail(f"CHANGELOG.md does not contain a section for {tag}")
    body = match.group("body").strip()
    if not body:
        fail(f"CHANGELOG.md section for {tag} is empty")
    return body


def validate_pubspec_version(tag: str) -> None:
    try:
        check_release_files(tag)
    except ReleaseVersionError as error:
        fail(str(error))


def validate_flutter_rust_bridge_lock() -> None:
    text = read_text("pubspec.lock")
    entry = re.search(
        r"^  flutter_rust_bridge:\s*\n(?P<body>(?:[ ]{4,}[^\n]*\n?)+)",
        text,
        re.MULTILINE,
    )
    body = entry.group("body") if entry else ""
    # Pub can label an identical direct dependency/override as direct main.
    # Check the selected package and version, not that serialization detail.
    direct = re.search(r'^    dependency: "?direct (?:main|overridden)"?\s*$', body, re.MULTILINE)
    version = re.search(r'^    version: "2\.11\.1"\s*$', body, re.MULTILINE)
    if not direct or not version:
        fail("pubspec.lock must lock direct flutter_rust_bridge version 2.11.1")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME", ""))
    parser.add_argument("--write-notes")
    args = parser.parse_args()

    tag = args.tag.strip()
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-rc\.\d+)?", tag):
        fail(f"Release tag must look like v1.2.3 or v1.2.3-rc.1, got {tag!r}")

    validate_pubspec_version(tag)
    validate_flutter_rust_bridge_lock()
    notes = extract_release_notes(tag)

    if args.write_notes:
        Path(args.write_notes).write_text(notes + "\n", encoding="utf-8")

    print(f"Release metadata for {tag} is valid")


if __name__ == "__main__":
    main()
