# Contributing

[简体中文](CONTRIBUTING.zh-CN.md)

For human and AI contributors. Read [project context](PROJECT_CONTEXT.md), then the
[development guide](docs/Development.md) and the architecture for the changed module.

## Verification and review

Run all project builds, tests, diagnostics and graphical verification **only in a dedicated
VM or hosted CI**, never on the maintainer workstation. Host Git and source editing are fine.
Candidate commits may be pushed to trigger CI. Merge and release require green checks;
publication additionally requires explicit maintainer authorization. See [release policy](docs/Releasing.md).

In the verification environment, run the contract and documentation checks and the relevant
layers of `tools/run-tests.sh`. UI changes also require `--all` and a real VM graphical session.
CI runs data/platform/logic/headless tests, the standard apps, and full KWin 6.6/6.7/6.8 SDK jobs.
SDK compilation and offline checks do not prove live compositor behavior.
Report the exact commit, environment, commands, results, skipped coverage and remaining limits.

## Main branch integration

Submit changes through a pull request and wait for every required check on the latest
commit before squash-merging. Main requires an up-to-date branch, forbids force pushes
and deletion, and does not require another person's approval. Administrator bypass is
reserved for emergencies, not ordinary integration. Merged PR branches are deleted automatically.

Required checks: `source release selection`, `data + platform + logic + headless`,
`Calendar Calculator Weather build and tests`, all three `KWin 6.6 / 6.7 / 6.8 SDK build and offline checks`
(matrix names are separate checks), `QML changed-file checks`, and `block-ai-coauthor`.
The QML job uses the PR base rather than working-tree status; an empty diff is reported
explicitly. It checks syntax and duplicate declarations, not full runtime/import correctness.
Compiled and runtime tests remain mandatory. Do not disable a valid check to obtain green CI.

## Change hygiene

- Inspect `git status --porcelain`, including untracked files, before staging. New QML, shaders,
  icons, native sources and packaging files are part of a working change; `git diff` alone misses them.
- Preserve unrelated user changes. Use a suitable branch/worktree and inspect its base before editing.
- Stage explicit paths, inspect the staged diff, and do not use `git commit -a`.
- Separate functional changes, documentation, and repository hygiene into reviewable commits.
- Search all references before deleting or moving files, including references in source comments.
- Keep reproducible regression tests in `tests/` or the owning module. Keep probes, captured logs,
  screenshots and session reports in ignored `tmp/` or external CI/Release artifacts.
- `.gitignore` covers stable generated paths; one-off scratch files belong in `tmp/`.
  Preserve third-party notices, licenses and asset provenance.

## Commit messages

Keep the human contributor as author and committer. A commit message must not carry an AI
attribution trailer (`Co-Authored-By` naming an AI service address such as
`noreply@anthropic.com`), and the author/committer email must not be an AI service address:
GitHub counts both toward the contributors panel. `.github/workflows/block-ai-coauthor.yml`
rejects new pull-request commits that match. To fix a rejected pull request, rewrite the
affected message (`git commit --amend` or a `git rebase -i` reword) and push with
`--force-with-lease`; the author stays unchanged.

## Documentation contract

[The documentation index](docs/README.md) identifies the canonical owner of each topic.
Architecture/development guides are operational context for **AI contributors**: describe current
ownership, contracts, source entry points, failure behavior and verification requirements.
Replace stale proposals and session narratives with current constraints. Do not present planned
behavior or unmeasured performance as implemented or verified.

English is the default. Keep Chinese companions of maintained bilingual guides in sync in the
same change. Release notes and installation/release/development entry points are bilingual.
Keep detailed topic documentation in one place and link it; avoid copying commands and mutable
release status across several guides. VERSION and immutable tags identify code; Release evidence
identifies actual validation. Historical results must retain their original scope.
