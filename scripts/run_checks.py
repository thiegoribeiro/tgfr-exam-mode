"""Build and run isolated logic/regression checks; never enable Exam Mode.

Requires Python 3.10+ and PowerShell 7 (pwsh). Windows interfaces are mocked;
passing these checks does not establish Windows deployment or enforcement.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--powershell", default="pwsh", help="PowerShell 7 executable or full path (default: pwsh)"
    )
    args = parser.parse_args()
    executable = shutil.which(args.powershell)
    if not executable:
        parser.error("PowerShell executable was not found; install pwsh or use --powershell PATH.")

    build = subprocess.run([sys.executable, str(ROOT / "scripts/build_release.py")], cwd=ROOT)
    if build.returncode:
        return build.returncode

    checks: list[tuple[str, list[str]]] = [
        (name, [str(ROOT / "tests" / name)])
        for name in (
            "test_app_control.ps1",
            "test_engine.ps1",
            "test_recovery.ps1",
            "test_ui_callbacks.ps1",
            "test_ui_startup.ps1",
            "test_rule_binding.ps1",
            "test_template_access.ps1",
        )
    ]
    checks.extend(
        [
            (
                "production-and-payload-gate",
                [
                    str(ROOT / "tests/test_no_legacy_backend.ps1"),
                    "-PackagedBatPath",
                    str(ROOT / "dist/TGFR_Exam_Mode_GUI_v7_0_2.bat"),
                ],
            ),
            (
                "original-rule-binding-failure",
                [
                    str(ROOT / "tests/test_rule_binding.ps1"),
                    "-SourcePath",
                    str(ROOT / "tests/fixtures/app_control_v7_0_baseline.ps1"),
                    "-ExpectOriginalFailure",
                ],
            ),
            (
                "original-template-access-failure",
                [
                    str(ROOT / "tests/test_template_access.ps1"),
                    "-SourcePath",
                    str(ROOT / "tests/fixtures/app_control_v7_0_1_baseline.ps1"),
                    "-ExpectOriginalFailure",
                ],
            ),
            (
                "packaged-help",
                [str(ROOT / "dist/embedded_payload_v7.ps1"), "-Action", "help"],
            ),
        ]
    )
    logs = ROOT / "dist/checks"
    logs.mkdir(parents=True, exist_ok=True)
    for name, script_args in checks:
        result = subprocess.run(
            [executable, "-NoLogo", "-NoProfile", "-File", *script_args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        output = result.stdout + result.stderr
        (logs / f"{name}.log").write_text(output, encoding="utf-8", newline="\n")
        if result.returncode:
            print(f"FAIL: {name} (exit {result.returncode})", flush=True)
            print(output, end="", flush=True)
            return result.returncode
        lines = [line for line in result.stdout.splitlines() if line.strip()]
        summary = (
            lines[0]
            if name == "packaged-help"
            else next(
                (line for line in reversed(lines) if "PASSED" in line or "passed" in line),
                lines[-1] if lines else "completed",
            )
        )
        print(f"PASS: {name}: {summary}", flush=True)

    print(
        f"All {len(checks)} isolated checks passed. Native Windows ConfigCI, "
        "policy enforcement, WinForms rendering and Microsoft Word were not tested.",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
