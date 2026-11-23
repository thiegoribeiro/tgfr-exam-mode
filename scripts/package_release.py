"""Build the curated, experimental 7.0.2 release assets.

Run with Python 3.10+ from a repository checkout or the public source ZIP.
Only the explicit public source allowlist below is archived. Generated logs,
Git metadata, machine recovery state and local upload metadata are excluded.
This script performs no GitHub, Windows policy or application-launch actions.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
OUT = DIST / "releases"
VERSION = "7.0.2"
ZIP_TIMESTAMP = (2026, 11, 23, 0, 0, 0)
SOURCE_NAME = "TGFR_Exam_Mode_v7_0_2_Public_Source.zip"
RELEASE_NAME = "TGFR_Exam_Mode_v7_0_2_Public_Release.zip"

# Update this reviewed list when adding public repository files. Do not replace
# it with a recursive workspace glob: local state must not become a release.
SOURCE_FILES = (
    ".gitattributes",
    ".gitignore",
    ".github/ISSUE_TEMPLATE/bug_report.yml",
    ".github/workflows/publish-experimental.yml",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "README.md",
    "SECURITY.md",
    "docs/DEVELOPMENT_JOURNAL.txt",
    "docs/USER_GUIDE.txt",
    "docs/architecture.md",
    "docs/release-notes-v7.0.2.md",
    "docs/windows-validation.md",
    "scripts/build_release.py",
    "scripts/package_release.py",
    "scripts/run_checks.py",
    "src/app_control.ps1",
    "src/engine.ps1",
    "src/main.ps1",
    "src/recovery_command.ps1",
    "src/ui.ps1",
    "src/word_exam.ps1",
    "tests/fixtures/app_control_v7_0_baseline.ps1",
    "tests/fixtures/app_control_v7_0_1_baseline.ps1",
    "tests/test_app_control.ps1",
    "tests/test_engine.ps1",
    "tests/test_no_legacy_backend.ps1",
    "tests/test_recovery.ps1",
    "tests/test_rule_binding.ps1",
    "tests/test_template_access.ps1",
    "tests/test_ui_callbacks.ps1",
    "tests/test_ui_startup.ps1",
)

# These hashes identify the already-reviewed 7.0.2 application bytes. A later
# application release must update its version, filenames and fingerprints.
LAUNCHERS = {
    "TGFR_Exam_Mode_GUI_v7_0_2.bat": (
        127159,
        "4563adac6e8e4c3a2fc1c5dd5e4a16ea413fb44007a4d21635a6fcf7341f7e51",
    ),
    "TGFR_Exam_Mode_Policy_Recovery_v7.bat": (
        10703,
        "e04d521199cb2ec704feab5943ca2a55a56fc404b8c5f498f8606fd5675f4ebd",
    ),
}
RELEASE_DOCS = (
    "USER_GUIDE.txt",
    "DEVELOPMENT_JOURNAL.txt",
    "release-notes-v7.0.2.md",
    "windows-validation.md",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_repo_file(relative_name: str) -> bytes:
    path = ROOT / relative_name
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Required regular public file is missing: {relative_name}")
    try:
        path.resolve().relative_to(ROOT.resolve())
    except ValueError as error:
        raise ValueError(f"Public file resolves outside the repository: {relative_name}") from error
    return path.read_bytes()


def write_verified_zip(path: Path, entries: dict[str, bytes]) -> None:
    if path.is_symlink():
        raise ValueError(f"Archive output must not be a symbolic link: {path.name}")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=ZIP_TIMESTAMP)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, entries[name], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None or sorted(archive.namelist()) != sorted(entries):
            raise ValueError(f"Archive integrity check failed: {path.name}")
        for name, expected in entries.items():
            if archive.read(name) != expected:
                raise ValueError(f"Archive entry differs from its source: {name}")


def main() -> int:
    subprocess.run([sys.executable, str(ROOT / "scripts/build_release.py")], cwd=ROOT, check=True)
    if len(SOURCE_FILES) != len(set(SOURCE_FILES)):
        raise ValueError("The public source allowlist contains a duplicate path.")
    public_sources = {name: read_repo_file(name) for name in SOURCE_FILES}
    launcher_bytes = {}
    for name, (expected_size, expected_hash) in LAUNCHERS.items():
        data = read_repo_file("dist/" + name)
        if len(data) != expected_size or digest(data) != expected_hash:
            raise ValueError(f"The generated launcher differs from reviewed {VERSION} bytes: {name}")
        launcher_bytes[name] = data

    release_entries = dict(launcher_bytes)
    for name in RELEASE_DOCS:
        release_entries[name] = public_sources["docs/" + name]
    release_entries["SHA256SUMS.txt"] = (
        "\r\n".join(digest(data) + "  " + name for name, data in launcher_bytes.items()) + "\r\n"
    ).encode("ascii")
    source_entries = {"tgfr-exam-mode/" + name: data for name, data in public_sources.items()}

    expected_assets = {*LAUNCHERS, SOURCE_NAME, RELEASE_NAME, "SHA256SUMS.txt"}
    OUT.mkdir(parents=True, exist_ok=True)
    for path in OUT.iterdir():
        if path.name not in expected_assets or path.is_symlink() or not path.is_file():
            raise ValueError(f"Unexpected item in generated release directory: {path.name}")

    write_verified_zip(OUT / SOURCE_NAME, source_entries)
    write_verified_zip(OUT / RELEASE_NAME, release_entries)
    for name, data in launcher_bytes.items():
        (OUT / name).write_bytes(data)
    asset_names = sorted([*LAUNCHERS, SOURCE_NAME, RELEASE_NAME])
    checksums = "\n".join(digest((OUT / name).read_bytes()) + "  " + name for name in asset_names) + "\n"
    (OUT / "SHA256SUMS.txt").write_text(checksums, encoding="ascii", newline="\n")
    for name in [*asset_names, "SHA256SUMS.txt"]:
        data = (OUT / name).read_bytes()
        print(json.dumps({"asset": name, "bytes": len(data), "sha256": digest(data)}), flush=True)
    print(
        f"Packaged {len(source_entries)} public source files and {len(release_entries)} release entries. "
        "Both archives were CRC/content verified. No native Windows operations were executed.",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
