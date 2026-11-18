# Glass rewrite working documents

Status: working documents for the ground-up Glass rewrite. They record the
target contract, the implemented state, the verification workflow and the
accepted debts. The published contract stays Window appearance; these pages
are the implementation notes behind it and are updated as the code changes.

- [Requirements](requirements.zh-CN.md)
- [Protocol rules](protocol.zh-CN.md)
- [Development and verification](development.zh-CN.md)
- [Pitfalls and performance debt](pitfalls.zh-CN.md)

Working rules:

- Verification is manual. Do not add unit, integration, UI, screenshot or
  headless-render tests for this work.
- Compile checks, shader compilation and static cross-checks are build steps,
  not tests.
- Temporary logs, captures and ledgers live under the repository `tmp/`
  directory, never in this tree.
- The published contract remains
  [Window appearance](../../../../docs/WindowAppearance.md), the
  [protocol XML](../../../../shell/native/surface-shape/kos-surface-shape-v1.xml)
  and the existing configuration/metadata files. When implementation lands,
  update those owners and promote these pages.
