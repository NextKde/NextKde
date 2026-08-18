# Independent desktop applications

Every direct child is a standalone Qt Quick application and a separate
process. Applications may import `shared/`, communicate with `services/`
through documented contracts, and must never import `desktop/`.

Planned applications: `calendar`, `todo`, `weather`, and `settings`.
