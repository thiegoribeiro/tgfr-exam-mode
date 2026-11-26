# J-015 — Cross-edition Windows acceptance findings and proposed improvements

**Report received:** 26 November 2026 (test execution dates not specified)  
**Application version under test:** not expressly confirmed; record provisionally against the latest published **7.0.2 experimental** pending the tester's confirmation of the exact BAT file and SHA-256.  
**Reporter:** TGFR / Thiego Ribeiro  
**Evidence:** user-reported results, not an independently reviewed test log or formal acceptance record.  
**Status:** partial pass; further investigation required.

## 1. Observed tests

| Environment as reported | Wi-Fi | Ethernet | VPN control | Excel | Calculator | Microsoft Store | Word spell-check |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Windows 10 Home 22H2 | Pass | Pass | Pass | Fail | Fail | Fail | Not reported |
| Windows 11 Home 24H2 | Pass | Pass | Pass | Fail | Fail | Fail | Not reported |
| Windows 11 "Pro Education" (exact edition/build not provided) | Pass (reported as all other features passing) | Pass (reported) | Pass (reported) | Pass (reported) | Pass (reported) | Pass (reported) | Fail — proofing remained active |

**Interpretation:** Pass/fail represents the tester's report. The VPN option's current documented scope is **VPN Settings-page visibility**, not proof that VPN client traffic or tunnels are blocked. The precise VPN test performed was not provided. "All features passed" on the third system is recorded as a broad user report; no detailed per-feature evidence was supplied. Windows 10 Home is not part of the current documented Windows 11 22H2+ application-control support target; failure there should not automatically be treated as a regression of a supported platform.

**Missing evidence:** exact release hash on each device, edition displayed by winver, cumulative OS update/build, Windows PowerShell language mode, installed desktop Office/Excel type and build, app/package versions, selected options, attempt details, device management policy summary, diagnostic messages, session/restart/recovery outcomes. No native Windows acceptance can be declared complete from the brief report alone.

## 2. Findings and work required

### A. Calculator / Excel / Microsoft Store blocking on Home editions
On both Home test systems, reported app blocks failed while selected network/settings options passed. Investigate Windows edition and policy-platform support, ConfigCI/CiTool availability, compilation, deployment and actual enforcement. Distinguish a genuine build/permission failure from an unsupported edition. Do **not** claim broad Home-edition support or replace WDAC with an unreliable filename-only control. Retain exact support-matrix limitations in README and tests.

### B. Word spelling/grammar enforcement on the Windows 11 Pro Education test
The current feature creates a prepared .docx exam copy with NoProof metadata; it is not an Office-wide or tamper-proof setting. Report says spelling check remained active. Reproduce with specific Word edition/build, prepared-vs-source document, existing/typed/pasted text, spell/grammar indicators and F7. Consider supported document-level, template/style and managed Office policy mechanisms, checking their effects and reversibility. Add automated document XML checks and native Word behavioural tests. Do not state that a registry-only option will enforce it across all Office installations.

### C. Optional Wi-Fi and VPN enable/reset controls from the legacy TGFR script
The reporter requests an optional **enable Wi-Fi / VPN** operation using the supplied older BAT 3.2 pattern. The example writes the `Value` DWORD under fourteen `HKLM\Software\Microsoft\PolicyManager\default` and `...\current\device` subkeys (six Wi-Fi and one Settings/AllowVPN setting in each branch), generally setting values to 1, except WLANScanMode=0, then offers a 30-second restart.

This is a **feature proposal, not a validated remediation**. Those entries may be default/reference or centrally managed state, and changing them does not necessarily enable Wi-Fi adapters, establish VPN access or override an enforced policy. The script also does not back up existing values, checks only the last command's `%errorlevel%` at the end, and could overwrite policy-managed state. Its restart is automatic after the timeout, not an exact configuration restore.

**Recommended design requirements:**
- Expose a separate, clearly named optional action such as **Re-enable previously disabled network settings** or **Repair network access (advanced)**, distinct from the normal recorded-state **Restore original state**.
- Primary pathway: restore per-adapter administrative state and the recorded VPN SettingsPageVisibility value using the existing reversible session journal.
- If any registry-based compatibility recovery is genuinely required, use an explicit supported-version/edition check; record each original key/value/type/absence; detect organisational policy ownership; provide a dry-run and per-write verification; decline ambiguous managed settings rather than forcing them to 1.
- Explain that **VPN Settings visibility is not VPN connectivity**. Test restoration with and without existing sessions and with centrally managed policy.
- Offer an opt-in, cancellable restart only where genuinely required; no unconditional reboot. Never destroy an existing recovery journal.

## 3. Proposed GitHub follow-up

1. Review app-control failures and support/edition matrix on Home systems; cross-link validation issue.
2. Fix and verify Word proofing in actual desktop Word on the tested Windows edition.
3. Design optional, reversible network re-enable and diagnostic behaviour rather than directly copying legacy PolicyManager registry writes.
4. Repeat full enable/verify/restore acceptance, including restart recovery and retained session state.
5. Gate v7.0.3 scope and release on confirmed fixes and compatibility testing.

## 4. Publication and security

Only edition names and test outcomes were shared; no raw logs, machine identifiers, school accounts or candidate data are included. Keep the actual original device policy and `session.json` private.

**Related:** [Full journal](../DEVELOPMENT_JOURNAL.txt), [Windows acceptance record](../windows-validation.md), [Validation issue #3](https://github.com/thiegoribeiro/tgfr-exam-mode/issues/3), [Restore issue #4](https://github.com/thiegoribeiro/tgfr-exam-mode/issues/4).
