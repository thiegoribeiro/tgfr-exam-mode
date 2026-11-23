# Development journal and GitHub Projects workflow

The **canonical public version history** is [DEVELOPMENT_JOURNAL.txt](DEVELOPMENT_JOURNAL.txt). This is a sanitised copy; never upload the original operational journal without reviewing it.

## Add a new journal entry

1. Open the [new entry template](JOURNAL_ENTRY_TEMPLATE.md).
2. Copy it into a new file under `docs/journal/`, named `YYYY-MM-DD-short-description.md`, using **Add file → Create new file** in the repository.
3. Write the objective, the reproducible symptoms, the changes and separate simulated versus native Windows evidence.
4. Commit the file on a feature branch, ideally through a pull request.
5. Update [DEVELOPMENT_JOURNAL.txt](DEVELOPMENT_JOURNAL.txt) with the release/incident summary and a link to the full new entry.
6. Link the entry to a GitHub issue and to the relevant pull request or release.

**Privacy:** Do not publish real school/student information, domain names, production policies, usernames, diagnostic logs, recovery data or credentials.

## Set up an actual GitHub Project board

The repository and its Issues are ready, but GitHub Projects boards are a separate product. In GitHub:

1. Open the **Projects** tab on your personal profile and choose **New project**.
2. Select **Board** and name it `TGFR Exam Mode — Development & Journal`.
3. Use workflow columns or a Status field: **Backlog → In progress → Testing → Done**.
4. Add the repository's tracking issue and subsequent bugs / feature requests to the Project.
5. Keep the journal text in repository Markdown files; a Project board manages work items and does not replace version-controlled journal files.
6. Optionally configure the Project's auto-add workflow to bring in new repository issues.

### Suggested Project views
- Board — current work by Status
- Table — all issues, versions, priorities and release targets
- Roadmap — future work with target dates, if needed

## First work items

- Run native Windows 11 enable/verify/restore acceptance tests.
- Confirm application-blocking results for Calculator, Microsoft Store and Excel.
- Record a tested disaster-recovery and restart procedure.
- Maintain release history, privacy checks and build validation.

See the [Windows validation checklist](windows-validation.md) before treating the software as production-ready.
