# TGFR Exam Mode 7.0.2 — experimental pre-release

Application prepared **20 November 2026**. Public repository preparation dated **23 November 2026**.

This release corrects protected-template handling during policy preparation and retains the rule-collection fix from 7.0.1. It remains an experimental preview requiring Windows acceptance testing.

## Changes

- Create a fresh writable working copy of the Windows `AllowAll.xml` template before ConfigCI processing.
- Keep the original template's contents, attributes, ownership and permissions unchanged.
- Use the working copy for executable and package-only planning.
- Distinguish an inability to read the Windows template from an inability to create the working copy.
- Add diagnostics for template preparation, rule merging and compilation.
- Retain individual native-rule extraction and typed `Rule[]` binding from 7.0.1.

Schema 7 and the existing policy ownership family remain unchanged. The v7 policy recovery launcher is compatible and its release bytes are unchanged from the prior v7 release.

## Files to keep together

- `TGFR_Exam_Mode_GUI_v7_0_2.bat` — main application.
- `TGFR_Exam_Mode_Policy_Recovery_v7.bat` — policy-only recovery if the normal GUI cannot open.

The BAT files contain the required PowerShell code. Python is used only for development/building, not to run the released application.

## Update and evaluate

1. Close the previous TGFR interface.
2. Preserve any active recovery record. Restore an active older session with its matching release; do not delete its journal.
3. Run the new main BAT as administrator and confirm version 7.0.2 in the title.
4. Select the required options, Enable, Verify and test actual application launches on a spare Windows device.
5. Restore and record the result, including any requested restart.

Application restrictions are device-wide, including administrators. Word proofing applies to the prepared document copy. VPN Settings visibility does not block VPN traffic. Read the [user guide](USER_GUIDE.txt) for the full scope and recovery procedure.

## Development evidence and limits

All 11 isolated development checks passed before publication.

The recorded development checks include four assertions reproducing the protected-input failure at a simulated ConfigCI boundary, 25 template-access assertions, 86 rule-binding assertions and 66 existing application-control assertions. Source/payload parsing and the removed-backend check passed, and the packaged help action identified 7.0.2.

These checks used PowerShell on Linux with Windows operations simulated. They did not execute the native Windows compiler, deploy/remove a real policy, launch blocked applications, render WinForms or run desktop Word. Complete and publish a [Windows acceptance record](windows-validation.md) before treating the preview as a stable deployment release.

## Main launcher fingerprint

```text
TGFR_Exam_Mode_GUI_v7_0_2.bat
Bytes: 127159
SHA-256: 4563adac6e8e4c3a2fc1c5dd5e4a16ea413fb44007a4d21635a6fcf7341f7e51
```

The fingerprint identifies the application bytes; it is not a code-signing certificate or proof of Windows acceptance.
