# Architecture and restoration design

TGFR Exam Mode distributes a BAT launcher with embedded PowerShell. The readable modules remain the source of truth; `scripts/build_release.py` combines them into the main launcher and a separate policy recovery launcher.

## Components

| Module | Responsibility |
| --- | --- |
| `src/main.ps1` | Entry point, supported actions and Windows/runtime prerequisites. |
| `src/ui.ps1` | Resizable WinForms interface, selections, status and diagnostics. |
| `src/engine.ps1` | Session ownership, baseline persistence, networking/settings changes, mutation lock and restoration. |
| `src/app_control.ps1` | Target discovery, policy planning, ConfigCI compilation, CiTool deployment and owned-policy verification/removal. |
| `src/word_exam.ps1` | Preparing a new Word document copy with supported proofing properties disabled. |
| `src/recovery_command.ps1` | Narrow policy-only recovery when the normal GUI cannot open. |

## Plan before applying changes

Enable checks prerequisites, existing sessions and selected applications before building a policy plan. The policy plan includes its own GUID, XML, compiled bytes, fingerprint and original policy inventory. Disposable compiler files are removed when planning ends.

The engine writes the baseline and intended plan into the protected machine journal before applying the generated policy or changing network/settings state. It records attempted operations so a partial failure can restore the changes that were actually attempted. A global mutation lock prevents simultaneous apply and restore operations.

The state file lives at `%ProgramData%\TGFR_ExamMode_v7\session.json`. Its contents include machine identity and policy information. It is operational recovery data and belongs outside the public repository.

## Application policy scope

The v7 backend uses a separate unsigned App Control for Business base policy. It starts from the Windows allow-all template, keeps allowance baselines and adds narrowly selected deny rules. Application restrictions apply to all users of the device. Existing independent policies remain in effect and are not rewritten by the app.

Windows Calculator and Store use exact package-family targets. Discovered desktop Excel and classic Calculator executable paths use validated file identities, with exact-hash fallback when suitable metadata is unavailable. The implementation refuses a shared Office package identity when that would prevent isolating Excel.

The current runtime contains no AppLocker policy operations or Application Identity service manipulation. The repository retains explanations of earlier designs for development context only.

### Two defects that shaped the planner

**7.0.1: collection binding.** ConfigCI can return a generic list as one pipeline object. Reading its members through PowerShell member enumeration can retain the list itself. The corrected planner explicitly extracts individual native rules, keeps the user-mode rules and supplies a typed `Rule[]` to the merge command. Tests exercise the real planning branch with a strict simulated parameter contract.

**7.0.2: protected input files.** The earlier planner passed the installed Windows `AllowAll.xml` directly to ConfigCI. A known protected-input compatibility problem can arise when the native operation requests write access to that input. The planner now reads the source bytes and creates a new writable file in its temporary build directory. It never changes the installed template's ownership, ACL or attributes. Separate errors distinguish source-read failure from working-copy creation failure.

See Microsoft's related [protected-input correction](https://github.com/MicrosoftDocs/WDAC-Toolkit/pull/407) and [Merge-CIPolicy parameter documentation](https://learn.microsoft.com/en-us/powershell/module/configci/merge-cipolicy).

## Restoration and ownership

Normal Restore works from the saved baseline. An adapter that was already administratively disabled remains disabled afterwards. Independently changed registry values are preserved for review rather than overwritten without checking.

Policy removal requires the saved deployment record, expected GUID/name, current inventory metadata and installed-file fingerprint. A matching non-system flag alone does not establish ownership. Signed, Windows-managed, externally changed or mismatched policies are not removed through this recovery path.

If removal is still active or persisted, the session stays available for recovery and the app may request a restart. It does not restart Windows automatically or manually delete an operating-system policy file to force completion. Successful restoration archives the journal and retains any prepared Word exam document or candidate answers.

The product version is **7.0.2**, while the journal schema remains **7** and the policy ownership name retains the **`TGFR Exam Mode 7.0`** family. Those identifiers are deliberately stable for compatibility.

## Policy-only recovery

The separate recovery launcher uses the protected session record to request removal of the recorded owned policy. It can run its recovery command under PowerShell ConstrainedLanguage without changing the language mode. It leaves networking, other settings and the journal intact. Normal Restore must finish the session afterwards.

Other device policies may still prevent PowerShell or CiTool from running. The recovery launcher does not override those policies.

## Test boundaries

The suite tests PowerShell logic, XML structure, ownership checks, state transitions, rollback decisions and selected UI behaviour with platform boundaries simulated. The fake ConfigCI types exist only in isolated test processes and are not built into the application.

Native compilation, deployed enforcement, physical adapters, displayed WinForms layout and desktop Word behaviour require target-device testing. Follow the [validation record](windows-validation.md) to keep those results distinct.
