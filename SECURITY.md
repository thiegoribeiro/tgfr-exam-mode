# Security reporting

TGFR Exam Mode runs with administrative privileges and changes machine settings. Security reports should describe a reproducible weakness in the code or its restoration behaviour without exposing a real institution's configuration.

## Current status

The current development line is the **7.x experimental preview**. Version 7.0.2 has source and simulated test evidence; native Windows acceptance is still pending. No production support commitment or guaranteed response time is offered.

The presence of earlier implementations in test fixtures or documentation does not indicate that those versions are maintained for deployment.

## Report a vulnerability privately

If GitHub private vulnerability reporting is available for this repository, open **Security → Advisories → Report a vulnerability** and submit the report there.

If that option is unavailable, use a private contact channel listed on [the maintainer's GitHub profile](https://github.com/thiegoribeiro). If no private channel is listed, open an issue requesting a private reporting channel without including vulnerability details or operational data.

Include the affected version, prerequisites, minimal reproduction, impact and a suggested correction if available. Use fictional or disposable test-machine details. Share only the minimum evidence needed to understand the issue.

## Keep recovery information private

Do not publish credentials, account/domain names, machine IDs, policy inventories, runtime `session.json` files, candidate work or raw institutional logs. Keep the original recovery journal on the affected device until restoration is complete. A sanitised public example must not replace the real record used for recovery.

## Ordinary bugs

UI layout problems, documentation errors and non-sensitive reproducible failures can use [GitHub Issues](https://github.com/thiegoribeiro/tgfr-exam-mode/issues). Follow the sanitisation instructions in [CONTRIBUTING.md](CONTRIBUTING.md).
