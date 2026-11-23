from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dist"
OUT.mkdir(exist_ok=True)
header = r'''@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem TGFR Exam Mode 7.0.2 - device-wide Windows App Control, network and Word.
rem Right-click and Run as administrator. No separate PS1 or Python required.
set "TGFR_SCRIPT=%~f0"
set "TGFR_ACTION=%~1"
set "TGFR_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "TGFR_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%TGFR_PS%" -NoLogo -NoProfile -STA -Command "if($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage'){Write-Error 'The GUI needs PowerShell FullLanguage. If a v7 session is active, run TGFR_Exam_Mode_Policy_Recovery_v7.bat as administrator, then reopen this app and Restore.';exit 1};$text=[IO.File]::ReadAllText($env:TGFR_SCRIPT);$marker=[Environment]::NewLine+'# TGFR_POWERSHELL_START'+[Environment]::NewLine;$index=$text.IndexOf($marker,[StringComparison]::Ordinal);if($index -lt 0){throw 'Embedded script marker is missing'};. ([scriptblock]::Create($text.Substring($index+$marker.Length))) -Action $env:TGFR_ACTION"
set "TGFR_EXIT=%errorlevel%"
if not "%TGFR_EXIT%"=="0" pause
exit /b %TGFR_EXIT%
# TGFR_POWERSHELL_START
'''
parts = ['param([string]$Action = "ui")\n$ErrorActionPreference = "Stop"\n$ProgressPreference = "SilentlyContinue"\n']
for name in ("word_exam.ps1", "app_control.ps1", "engine.ps1", "ui.ps1", "main.ps1"):
    parts.append(f"\n# ===== {name} =====\n" + (ROOT / "src" / name).read_text(encoding="utf-8"))
payload = "\n".join(parts)
text = header + payload
for forbidden in ("applocker", "appidsvc", "application identity"):
    assert forbidden not in text.lower(), forbidden
raw = text.replace("\r\n", "\n").replace("\n", "\r\n").encode("ascii")
assert raw.count(b"\r\n# TGFR_POWERSHELL_START\r\n") == 1
assert b"\n" not in raw.replace(b"\r\n", b"")
assert max(map(len, header.splitlines())) < 8191
target = OUT / "TGFR_Exam_Mode_GUI_v7_0_2.bat"
target.write_bytes(raw)
(OUT / "embedded_payload_v7.ps1").write_text(payload, encoding="utf-8", newline="\n")
print(f"{target.name}: {len(raw)} bytes, SHA256 {hashlib.sha256(raw).hexdigest()}")

recovery_header = r'''@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem TGFR Exam Mode 7.0 - owned-policy recovery, including constrained PowerShell.
rem Right-click and Run as administrator. Keeps the journal for normal Restore.
set "TGFR_RECOVERY_SELF=%~f0"
set "TGFR_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "TGFR_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%TGFR_PS%" -NoLogo -NoProfile -Command "$text=Get-Content -LiteralPath $env:TGFR_RECOVERY_SELF -Raw -ErrorAction Stop;$parts=$text -split '\r?\n# TGFR_RECOVERY_START\r?\n',2;if($parts.Count -ne 2){throw 'Recovery payload marker is missing'};Invoke-Expression $parts[1]"
set "TGFR_EXIT=%errorlevel%"
echo.
pause
exit /b %TGFR_EXIT%
# TGFR_RECOVERY_START
$ErrorActionPreference='Stop'
'''
recovery_entry = '''
try {
    $code=Invoke-TgfrPolicyRecovery
    exit $code
} catch {
    Write-Host ('RECOVERY STOPPED: '+$_.Exception.Message) -ForegroundColor Red
    Write-Host 'The session journal has been retained. No other policy IDs were selected for removal.'
    exit 1
}
'''
recovery = recovery_header + (ROOT / "src" / "recovery_command.ps1").read_text(encoding="utf-8") + recovery_entry
for forbidden in ("applocker", "appidsvc", "application identity"):
    assert forbidden not in recovery.lower(), forbidden
recovery_bytes = recovery.replace("\r\n", "\n").replace("\n", "\r\n").encode("ascii")
assert recovery_bytes.count(b"\r\n# TGFR_RECOVERY_START\r\n") == 1
recovery_path = OUT / "TGFR_Exam_Mode_Policy_Recovery_v7.bat"
recovery_path.write_bytes(recovery_bytes)
print(f"{recovery_path.name}: {len(recovery_bytes)} bytes, SHA256 {hashlib.sha256(recovery_bytes).hexdigest()}")

# Reproducible fingerprints for the two downloadable launchers.
(OUT / "SHA256SUMS.txt").write_bytes(("\r\n".join(
    hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name
    for path in (target, recovery_path)
) + "\r\n").encode("ascii"))
