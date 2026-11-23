# Changelog

This public changelog summarises application changes. Dates refer to application development unless marked as repository preparation. Experimental releases require target-device acceptance testing.

## Public repository preparation — 2026-11-23

- Organised readable source modules, regression tests and build tooling for review.
- Added public usage, architecture, validation and contribution documentation.
- Removed operational account details from public incident examples.
- Identified the current application as an experimental pre-release. No new claim of native Windows enforcement validation is made.

## 7.0.2 — 2026-11-20

### Fixed

- Read the installed Windows `AllowAll.xml` template and create a new writable temporary copy before passing it to ConfigCI.
- Use the working copy for both executable and package-only policy preparation, preserving the source template's contents, attributes and permissions.
- Report separate failures for reading the Windows template and creating the temporary copy.

### Changed

- Added diagnostics for template preparation, rule merging and compilation.
- Updated the interface and help version to 7.0.2 while keeping schema 7 and the `TGFR Exam Mode 7.0` policy ownership family compatible with v7 recovery records.

### Development verification

- Added a protected-input regression with a simulated ConfigCI boundary, covering writable copies, original bytes and attributes, cleanup and read/create failures.
- Retained the 7.0.1 rule-list correction and existing application-policy tests.
- Native Windows compilation, enforcement, UI and Word acceptance remain unconfirmed in the recorded development environment.

## 7.0.1 — 2026-11-20

### Fixed

- Explicitly flatten ConfigCI rule arrays and lists into individual native rule objects before filtering by `UserMode`.
- Pass a typed `Rule[]` to `Merge-CIPolicy`, avoiding conversion of an entire `List<Rule>` into one rule.
- Require usable user-mode rules for every selected executable and reject unexpected return objects.

### Development verification

- Added strict typed-parameter fixtures that reproduce the original conversion failure and exercise scalar, array, generic-list and nested-list output.
- Preserved existing v7 session and policy ownership compatibility.

## 7.0 — 2026-11-20

### Changed

- Replaced the earlier application-control backend with a separate device-wide App Control for Business policy managed through ConfigCI and CiTool.
- Removed AppLocker operations and Application Identity service prerequisites from the current production implementation.
- Introduced a separate schema 7 session journal and ownership/fingerprint checks for policy removal.
- Added a standalone policy recovery launcher and documented its limited role before normal restoration finishes.
- Retained physical adapter controls, VPN Settings visibility and separate Word exam document preparation.

## Earlier development

Earlier 3.x–6.x iterations explored registry settings, a selectable interface, networking, proofing preferences and a different application-control backend. Their state formats and recovery behaviour differ from version 7. An active older session must be recovered with its matching release; the current app does not import an old baseline or guess its original values.
