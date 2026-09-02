# Independent desktop applications

Every direct child is a standalone Qt Quick application and a separate
process. Applications may import `shared/`, communicate with `services/`
through documented contracts, and must never import `shell/desktop/`.

`settings` is the first full consumer of the Shell IPC contract. `calendar`,
`todo`, and `weather` are planned placeholders (README only for now).
