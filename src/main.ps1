# Entry point. The BAT dot-sources the embedded payload so WinForms closures
# resolve the engine functions in the same PowerShell process.
if ([string]::IsNullOrWhiteSpace($Action)) { $Action='ui' }
if ($Action -in @('help','--help','/?')) {
    @'
TGFR EXAM MODE 7.0.2 - 20 November 2026

USAGE
  TGFR_Exam_Mode_GUI_v7_0_2.bat          Open the interface
  TGFR_Exam_Mode_GUI_v7_0_2.bat verify   Print current configuration checks
  TGFR_Exam_Mode_GUI_v7_0_2.bat restore  Restore the saved v7 session

APPLICATION CONTROL
Version 7 uses App Control for Business (WDAC) through native CiTool and the
ConfigCI policy tools. It creates a separate unsigned policy with its own ID
for this exam session. Application restrictions affect THE WHOLE COMPUTER,
including administrators and every signed-in account. There is no exam-user
selector because this application-control mechanism has device-wide scope.

Application blocking requires Windows 11 22H2 or newer with the native
CiTool.exe and ConfigCI components available. Run this BAT as administrator.
No application-control service startup setting is changed by this version.
Existing policies remain independently managed. This version installs and
removes only its own recorded exam policy, subject to recovery verification.

Select Calculator, Microsoft Store and/or Excel as needed. Close the selected
applications in ALL signed-in sessions first. Select Enable selected to apply
the selected restrictions. An already-running application is not terminated
by this app. Save work before starting an exam session.

Calculator and Store use installed package identities. Classic Calculator
and desktop Excel use discovered executable identities. This does not block
browser calculators, web Excel or every third-party calculator program.
An MSIX-packaged Office installation cannot isolate Excel from Word through
one shared package identity. If that installation is detected, this release
reports the limitation instead of blocking the entire Office package.
Verify checks the owned policy and recorded state; it is not a launch test.
Test the selected blocked applications and required exam applications on the
actual Windows device before using the configuration for an examination.

RESTORATION AND RESTARTS
The v7 baseline and policy identity are saved before the exam policy is
installed or network/settings writes begin:
  %ProgramData%\TGFR_ExamMode_v7\session.json
Restore removes the recorded exam policy and restores recorded settings.
Windows can require a restart to finish policy removal, depending on its
build and update level. Follow the reported pending-restart instructions,
then run Restore/Verify again. There is no automatic reboot.

If any recovery operation fails or remains pending, the journal is retained.
Keep it until restoration completes. Independently changed settings and
policies are preserved for review. The ordinary session-status display is
not continuous application monitoring.

If the GUI cannot open during a v7 session, run the companion
TGFR_Exam_Mode_Policy_Recovery_v7.bat as administrator. This checks the protected
v7 record and removes only its owned unsigned policy. It can run with
ConstrainedLanguage restrictions, without changing that language mode.
It retains the journal and does not restore networking or other settings.
After policy recovery and any requested restart, reopen this app and select
Restore to complete recovery. Other policies can still impose restrictions.

BEFORE MOVING FROM AN OLDER RELEASE
An active v6 session must be restored with its matching release before
enabling a new v7 session. The new version checks for that older journal but
does not import its application-policy backend or guess its original state.
Keep the earlier executable and recovery files until that session is closed.
Use the matching older release to recover v4/v5 backups as well.

WORD - DO NOT CHECK SPELLING OR GRAMMAR
On the Word exam document tab choose a blank answer document or an existing
ordinary .docx. Choose a NEW output filename. Select Prepare Word exam copy
and Enable selected. OPEN THAT COPY for the examination.
The prepared copy's supported text, paragraph marks, styles and defaults
receive w:noProof=true. The original document is not overwritten. Restore
retains the exam copy and student answers.
Signed, protected, encrypted, macro/embedded-content documents and unsupported
DrawingML text are refused. Use a plain exam .docx prepared by the exam team.
Confirm in desktop Word: Ctrl+A > Review > Language > Set Proofing Language >
Do not check spelling or grammar. Test new typing and F7 before the exam.
Pasting formatted text or changing language/proofing settings can re-enable
checking. Another document, Office web, PowerPoint, Outlook, AutoCorrect and
add-ins are not disabled by this document setting.

NETWORK
Wi-Fi/Ethernet disable identified physical adapters and record their GUIDs
and administrative states. Adapters already disabled remain disabled after
restore. Newly attached adapters and other network paths are not covered.
VPN hides the Windows VPN Settings page for the device. It does not block
VPN clients or VPN traffic. Network options affect the whole machine.
Disabling Wi-Fi and Ethernet disconnects remote access. Test locally.

INTERFACE
The resizable window is clamped to the monitor working area. Restriction and
Word options scroll inside tabs. The action buttons and status remain in a
docked footer. Diagnostics text wraps so long messages remain readable.
Use Copy diagnostics to report exact policy and recovery results.

VALIDATION LIMITS
The development environment uses PowerShell on Linux for syntax and logic
checks with simulated Windows boundaries. Native Windows policy deployment,
application launches, WinForms rendering and desktop Word behavior must be
verified on the target Windows device. A successful configuration check is
not proof that every possible application launch route was tested.

PRIMARY REFERENCES
https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/create-appcontrol-deny-policy
https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/manage-packaged-apps-with-appcontrol
https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/citool-commands
https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/deployment/disable-appcontrol-policies
https://learn.microsoft.com/en-us/office/vba/api/word.range.noproofing
'@
    return
}
if ($env:OS -ne 'Windows_NT') { throw 'TGFR Exam Mode runs on Windows. No system settings have been changed.' }
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -lt 1) { throw 'Run the BAT launcher with built-in Windows PowerShell 5.1.' }
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use the BAT launcher to start native 64-bit Windows PowerShell.' }
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw 'The current Windows policy restricts required PowerShell features. Deploy through the approved management context; this tool does not change that policy.' }
try {
    switch ($Action.ToLowerInvariant()) {
        'ui' { Show-TgfrInterface }
        'verify' {
            $result=Get-TgfrVerification
            Write-Output $result.Message
            $result.Lines | Write-Output
            if (-not $result.Ok) { exit 1 }
        }
        'restore' { Invoke-TgfrRestore | Write-Output }
        default { throw 'Unknown action. Use ui, verify, restore or help.' }
    }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
