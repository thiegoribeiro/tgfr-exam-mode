# Contributing

TGFR Exam Mode is an experimental project. Useful contributions include reproducible Windows test results, focused bug fixes, clearer documentation and regression tests for observed failures.

An open-source licence has not yet been selected. Discuss substantial contributions and their licensing with the maintainer before submitting them.

## Report an ordinary bug

Open an issue using the bug-report form. Include:

- Application version and the operation that failed: Enable, Verify, Restore, policy recovery or startup.
- Windows edition, build and update level; the relevant Office installation type and version.
- Selected options, minimal reproduction steps, expected result and actual result.
- A sanitised error excerpt and whether a saved session or pending restart remains.

Replace real account names, domain names, hostnames, machine identifiers, policy identifiers, user document paths and other identifying details with consistent fictional placeholders. Do not attach `session.json`, full policy inventories, candidate documents or raw operational logs to a public issue. Preserve the originals privately for local recovery.

Use the process in [SECURITY.md](SECURITY.md) for vulnerability reports.

## Work on the code

1. Create a branch for a focused change.
2. Keep the production source in `src/`; generated BAT files come from the build script.
3. Preserve compatibility with Windows PowerShell 5.1 in production modules.
4. Add or adjust a regression test when it demonstrates the behaviour being corrected.
5. Build and run the relevant checks from the repository root:

```sh
python3 scripts/build_release.py
python3 scripts/run_checks.py
```

Use `--powershell /path/to/pwsh` when the test PowerShell executable is not on `PATH`. On Windows, use `python` if your installation provides that command.

Tests replace platform operations at explicit boundaries. They must not install a policy, disable networking, alter the host registry or run an actual exam session on a contributor or CI machine. Keep synthetic fixtures separate from production code. The historical planner files under `tests/fixtures/` exist to reproduce defects; they are not release implementations.

## Explain a proposed change

A pull request should state the problem, the change in behaviour, how it was checked and any remaining limits. Separate simulated test results from observations made on a Windows test device.

For native testing, complete the relevant parts of [Windows validation](docs/windows-validation.md). Use a spare device and keep recovery available. Do not report application enforcement as verified solely because policy deployment or configuration verification succeeded.

## Preserve restoration behaviour

Changes must retain the recorded baseline until restoration is complete. They must not remove unrelated policies, overwrite an existing answer document, broaden an executable deny to the whole Office suite, or discard a recovery journal to clear an error.

Keep public changes and fixtures free of organisation-specific data. The repository does not include a deployment endorsement or an examination compliance claim.
