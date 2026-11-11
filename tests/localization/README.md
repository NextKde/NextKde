# System UI language

The Shell and Settings follow the primary system UI language
(`Qt.locale().uiLanguages`) unless Settings → Theme pins `zh-CN`, `pt-BR` or `en`.
On Linux, Qt derives the system value from `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`
and `LANG`. A primary `zh` language selects Chinese, `pt` selects Brazilian
Portuguese, and other primary languages select English. Secondary fallbacks do
not override the primary language. User content and provider identifiers retain
their original language; dates use the selected UI locale.

Independent application catalogs, startup rules and capture tools are maintained
in [their owning repositories](../../apps/README.md). Core no longer carries
capture commands for the removed monorepo binaries or the retired Todo app.

## Catalogs

| Surface | Chinese | Brazilian Portuguese |
|---|---|---|
| Shell and Settings (`I18n.tr`) | `shared/qml/i18n/ZhCatalog.mjs` | `shared/qml/i18n/PtBrCatalog.mjs` |
| Independent apps | Catalogs owned by [their repositories](../../apps/README.md) | Catalogs owned by their repositories |
| KWin glass effect | `kwin/glass-effect/po/zh_CN/` | `kwin/glass-effect/po/pt_BR/` |

The Chinese catalogs must cover every source string. The Portuguese catalogs may
lag behind: a missing entry falls back to English, but every entry present must
match a current source string and keep its placeholders. ListenFree's English
catalog is generated from `en_US.tsv` by
the independent [ListenFree repository](https://github.com/NextKde/ListenFree).

## Checks

- App catalog extraction/placeholder checks are owned and run by the independent app repositories.
- `node tests/localization/widget-language.mjs`: the shared QML primary-language policy and literal Shell/Settings translation calls, including dictionary coverage and placeholders; reports untranslated pt-BR Shell strings.
- `ctest --test-dir BUILD -R language --output-on-failure`: core Shell language tests; app suites run in their repositories.
- ListenFree's standalone build with `LISTENFREE_BUILD_TESTS=ON` adds
  `listenfree.language.*`, including saved-language override regression tests.

## Actual layout captures

`capture_widgets.py` uses a temporary platform service and the actual widget
items. It requires a Wayland desktop; `KOS_QUICKSHELL_BIN` can select a custom
Quickshell binary. Use `--size small` to check compact widgets. The render window
is temporary; widget settings are never written to the installed shell.
`KOS_SHELL_DIR` can select a staged or installed shell tree.

All captures cover Chinese, English, and French (English fallback), writing
PNGs and logs to `.build/language-qa`. Visually inspect the screenshots as well
as the log checks: text can be clipped without causing a QML warning.
