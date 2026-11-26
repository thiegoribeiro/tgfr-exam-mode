# Windows acceptance record

## Current status

**No completed native Windows acceptance record is included in the initial public preparation dated 23 November 2026.** Application version 7.0.2 has source inspection and simulated regression evidence. The recent rule-list and protected-template errors were reproduced at controlled test boundaries; native ConfigCI compilation and application enforcement were not executed in the development environment.

A passing simulated suite establishes only the behaviours it exercises. The application's Verify action checks configuration and recorded state; it does not prove every launch route is blocked.

## Field results reported 26 November 2026 — partial / unverified

See [the dated J-015 test entry](journal/2026-11-26-cross-edition-testing.md) and [development journal rev. 1.5](DEVELOPMENT_JOURNAL.txt).

| Reported environment | Wi-Fi | Ethernet | VPN option | Excel | Calculator | Store | Word spelling/grammar |
|---|---|---|---|---|---|---|---|
| Windows 10 Home 22H2 | Pass | Pass | Pass | Fail | Fail | Fail | Unreported |
| Windows 11 Home 24H2 | Pass | Pass | Pass | Fail | Fail | Fail | Unreported |
| Windows 11 "Pro Education" (exact edition/build unspecified) | Pass (broad user report) | Pass | Pass | Pass | Pass | Pass | Fail |

**Evidence status:** user-reported results; no full native run logs, test hashes, installed Office versions, exact tested selections, or complete restore results were supplied. The main test cases below remain **Not tested / not formally recorded**, meaning this update does not falsely certify end-to-end acceptance. The VPN option means **VPN Settings-page visibility**, not guaranteed VPN connectivity blocking. Windows 10 Home is outside the current Windows 11 22H2+ documented app-control requirement. The precise label "Pro Education" is preserved as reported and requires OS edition confirmation. Application version is presumed to be the current 7.0.2 experimental build but its hash was not supplied; do not treat that inference as verified.

**Next action:** reproduce each reported failure on documented builds, validate native enforcement and Word proofing, complete session restoration and restart testing, then update individual acceptance-case outcomes with per-device evidence.

## Record the test environment

Use a spare workstation with local access and keep the matching recovery launcher available. Retain full recovery information privately; use anonymised values in a published report.

| Field | Record |
| --- | --- |
| Application version and SHA-256 | Not yet recorded |
| Windows edition, build and update level | Not yet recorded |
| Device description or fictional reference | Not yet recorded |
| Windows PowerShell version and language mode | Not yet recorded |
| Office installation type and version | Not yet recorded |
| Calculator and Store package versions | Not yet recorded |
| Relevant existing management policies | Summarise without publishing policy inventory or identifiers |
| Selected options | Not yet recorded |
| Test date and tester | Not yet recorded |

## Acceptance cases

Mark each case **Pass**, **Fail** or **Not tested**, with a short observation. Do not replace an untested case with an assumption.

| Case | Expected observation | Result |
| --- | --- | --- |
| Startup and layout | Controls, action buttons, status and diagnostics remain accessible at the device's resolution and scaling. | Not tested |
| Application preparation | Selected executable/package rules compile and an owned policy is recorded before deployment. | Not tested |
| Calculator selection | Installed Windows Calculator and the discovered classic targets cannot launch after closing existing instances. | Not tested |
| Store selection | The named Microsoft Store application cannot launch after closing existing instances. | Not tested |
| Desktop Excel selection | Desktop Excel cannot launch; required Word and other permitted applications still work. | Not tested |
| All-user scope | The selected application restrictions behave as documented in the intended exam account and other relevant signed-in accounts. | Not tested |
| Wi-Fi / Ethernet selection | Selected physical adapters are administratively disabled; record their initial states privately. | Not tested |
| VPN Settings selection | The VPN Settings page is hidden; this case makes no claim about VPN traffic blocking. | Not tested |
| Word copy preparation | A new output document is created, the original remains unchanged, and the prepared copy opens correctly. | Not tested |
| Word proofing behaviour | Check the proofing setting, new typing and F7 in the prepared copy; record the effect of pasted formatting as a known boundary. | Not tested |
| Normal Restore | Recorded networking/settings return to their original states and the owned policy is removed; unrelated policies remain. | Not tested |
| Original disabled adapter | An adapter disabled before the exam remains disabled after restoration. | Not tested |
| Restart-assisted Restore | If Windows reports pending removal, recovery survives a restart and Restore completes afterwards. | Not tested |
| Policy recovery launcher | On a controlled recovery scenario, it removes only the recorded policy and leaves the journal for normal Restore. | Not tested |
| Answer preservation | Prepared documents and entered candidate work remain after Restore or an apply failure. | Not tested |
| Repeat session | A completed restoration permits a new session without reusing or overwriting an active baseline. | Not tested |

For failures, record the last completed stage, exact sanitised error, whether changes were attempted, the recovery action and the resulting state. Preserve the original session journal privately. Do not delete it to clear a warning.

## Publishing a result

A useful report includes the environment above, exact tested selections, actual blocked and permitted application launches, restoration outcome and any remaining untested cases. Remove institutional details and candidate data. Include the version and checksum so the result refers to specific code.

Use wording such as “Calculator and desktop Excel launch/restore tested on the recorded Windows build.” Avoid general claims that all Windows, Office configurations or possible launch routes have been validated.
