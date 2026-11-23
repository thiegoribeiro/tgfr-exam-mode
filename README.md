# TGFR Exam Mode

An experimental Windows utility for preparing an exam workstation and restoring its recorded settings afterwards. Maintained by **TGFR / Thiego Ribeiro**.

**Current application: 7.0.2 — experimental pre-release.** The source and simulated regression tests have been checked during development. Native Windows policy compilation, application blocking, WinForms rendering and desktop Word behaviour still need recorded acceptance testing. See [validation status](docs/windows-validation.md).

Application restrictions affect **every user of the computer, including administrators**. This project is a development tool for IT administrators; it does not claim examination certification or approval by an awarding body.

## Features and scope

| Option | Implemented behaviour | Boundary |
| --- | --- | --- |
| Windows Calculator | Creates denies for the named Windows Calculator package and discovered classic Calculator executables. | Browser calculators and unrelated third-party calculators are outside the selected targets. |
| Microsoft Store | Targets the named Microsoft Store package. | Other software installation routes are not covered. |
| Microsoft Excel | Targets discovered desktop Excel using narrow file identity rules, with hash fallback where necessary. | Web Excel is outside scope. Shared-identity packaged Office is refused when Excel cannot be isolated from the suite. |
| Wi-Fi / Ethernet | Disables identified physical adapters and records their original administrative states. | New adapters and other network paths are not automatically added to a running session. |
| VPN Settings | Hides the Windows VPN Settings page. | Does not block VPN traffic or third-party VPN clients. |
| Word proofing | Creates a separate `.docx` exam copy with supported text and styles marked **Do not check spelling or grammar**. | A document setting, not an Office-wide lock. Formatting changes or pasted content can re-enable checking. |
| Restore | Restores recorded settings and removes only the session's verified, owned application policy. | Recovery may require a restart. The journal stays available until recovery completes; answer documents are retained. |

Application control uses **App Control for Business (WDAC), ConfigCI and CiTool**. The current application and recovery launcher contain no AppLocker commands or Application Identity service changes.

## Requirements

- Application restrictions require **Windows 11 22H2 or later**, with the native CiTool and ConfigCI components available.
- Run the BAT launcher **as administrator**. It starts the built-in **Windows PowerShell 5.1**; a separate Python installation or `.ps1` file is not needed to run a release.
- The normal GUI requires PowerShell **FullLanguage**. The separate policy recovery launcher supports a constrained-language recovery path without changing the language mode.
- Close selected applications in **all signed-in sessions** before enabling restrictions.
- Evaluate on a spare device with local access. Disabling Wi-Fi and Ethernet can disconnect remote support.

Existing device policies remain independently managed and can affect the result.

## Download and use

Use the [GitHub Releases page](https://github.com/thiegoribeiro/tgfr-exam-mode/releases) for published pre-release downloads, or build the BAT files from source below.

1. Extract the files into a local folder and keep the main and recovery launchers together.
2. If an earlier TGFR session is active, restore it with its matching release first. Preserve its recovery record.
3. Right-click `TGFR_Exam_Mode_GUI_v7_0_2.bat` and select **Run as administrator**.
4. Choose the required options. For Word, choose a source document or blank document and a **new** output filename; open that prepared copy for the examination.
5. Select **Enable selected**, then **Verify**.
6. Test actual launches of both the selected blocked applications and the applications candidates must be able to use. Verify checks configuration; it does not launch applications to prove enforcement.
7. After evaluation, select **Restore original state** and follow any restart instructions.

Read the [full user guide](docs/USER_GUIDE.txt) before deployment.

### Recovery

The current session record is stored at:

```text
%ProgramData%\TGFR_ExamMode_v7\session.json
```

Keep that record until restoration completes. If the GUI cannot open during a v7 session, run `TGFR_Exam_Mode_Policy_Recovery_v7.bat` as administrator. It checks the session's recorded policy identity and requests removal of that policy only. **This recovery launcher does not restore network adapters or other settings.** After policy recovery and any requested restart, reopen the main application and select **Restore original state**.

The app does not restart the computer automatically. A failure or pending removal retains the journal. Recovery files can contain machine and policy identifiers; keep them private.

### Command-line actions

```bat
TGFR_Exam_Mode_GUI_v7_0_2.bat help
TGFR_Exam_Mode_GUI_v7_0_2.bat verify
TGFR_Exam_Mode_GUI_v7_0_2.bat restore
```

## Build and check the source

Development requires Python 3.10 or later and PowerShell 7. The regression suite uses simulated Windows boundaries and can run on Linux; the distributed application still targets Windows PowerShell 5.1.

```sh
python3 scripts/build_release.py
python3 scripts/run_checks.py
python3 scripts/package_release.py
```

If PowerShell is not on `PATH`, supply its executable:

```sh
python3 scripts/run_checks.py --powershell /path/to/pwsh
```

On Windows, use `python` instead of `python3` if that is your installed command. Generated launchers are written to `dist/`; the verified public packages and download checksums are written to `dist/releases/`.

The readable modules are in [src/](src/), regression tests and fictional fixtures are in [tests/](tests/), and build tooling is in [scripts/](scripts/). Native Windows acceptance is a separate activity: complete the [Windows validation record](docs/windows-validation.md) rather than interpreting a passing simulated suite as proof of enforcement.

### Experimental release publishing

The [publishing workflow](.github/workflows/publish-experimental.yml) runs the simulated checks, packages the public files and publishes `v7.0.2-experimental`. It runs when that workflow file changes on `main`, or when the maintainer starts it manually from GitHub Actions. It uses GitHub's built-in repository token and requires no personal access token. An existing release with that tag is preserved; publishing a later version requires updating the version-specific packaging and workflow. A green workflow confirms the development checks and packaging, not native Windows acceptance.

## Documentation

- [Architecture and restoration design](docs/architecture.md)
- [Windows validation plan and current status](docs/windows-validation.md)
- [7.0.2 release notes](docs/release-notes-v7.0.2.md)
- [Public changelog](CHANGELOG.md)
- [Development journal, public edition](docs/DEVELOPMENT_JOURNAL.txt)
- [Contributing and reporting ordinary bugs](CONTRIBUTING.md)
- [Reporting security concerns](SECURITY.md)

## Project status and licence

This initial public preparation is dated **23 November 2026**. The 7.0.2 application was prepared on **20 November 2026**. Known gaps and observed defects are recorded rather than presented as completed Windows validation.

An open-source licence has not yet been selected.
