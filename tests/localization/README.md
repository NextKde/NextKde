# System UI language

Calendar, Todo, Weather, ListenFree, and their desktop widgets use the primary
system UI language (`QLocale::system().uiLanguages()`, or `Qt.locale().uiLanguages`
in the shell). On Linux, Qt derives this from the process environment, including
`LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, and `LANG`; no saved user profile is required.
A `zh` language, including regional/script variants, selects
Chinese; a `pt` language, including `pt_PT`, selects Brazilian Portuguese;
every other primary language selects English. A secondary fallback does not
override the primary language. The Shell and Settings can also pin the
interface language (`auto`, `zh-CN`, `pt-BR` or `en`) in Settings → Theme.
ListenFree has no Portuguese catalog yet, ignores old saved language selections
and excludes language from settings imports.

Applications choose the language at startup. Relaunch them after changing the
system UI language; restart the shell or sign in again for desktop widgets.
User content, song metadata, and provider API identifiers keep their original
language. Dates and weekdays use the same selected UI locale.

The common apps embed their Qt Linguist catalogs. Building needs Qt LinguistTools;
translated standard dialog buttons additionally use the system Qt translations
package (`qt6-translations` or `qt6-translations-l10n`).

## Catalogs

| Surface | Chinese | Brazilian Portuguese |
|---|---|---|
| Shell and Settings (`I18n.tr`) | `shared/qml/i18n/ZhCatalog.mjs` | `shared/qml/i18n/PtBrCatalog.mjs` |
| Calendar, Todo, Weather, Calculator | `apps/common/translations/kos_apps_zh_CN.ts` | `apps/common/translations/kos_apps_pt_BR.ts` |
| KWin glass effect | `kwin/glass-effect/po/zh_CN/` | `kwin/glass-effect/po/pt_BR/` |

The Chinese catalogs must cover every source string. The Portuguese catalogs may
lag behind: a missing entry falls back to English, but every entry present must
match a current source string and keep its placeholders. ListenFree's English
catalog is generated from `en_US.tsv` by
`apps/listenfree/tools/compile_translations.py`.

## Checks

- `python tests/localization/check_catalogs.py`: extracted UI messages and placeholders; reports untranslated pt_BR app messages.
- `node tests/localization/widget-language.mjs`: the shared QML primary-language policy and literal Shell/Settings translation calls, including dictionary coverage and placeholders; reports untranslated pt-BR Shell strings.
- `ctest --test-dir BUILD -R language --output-on-failure`: app and shell language tests.
- ListenFree's standalone build with `LISTENFREE_BUILD_TESTS=ON` adds
  `listenfree.language.*`, including saved-language override regression tests.

## Actual layout captures

`capture_apps.py` expects the three app binaries in `.build/language-apps`.
`capture_apps.py --music` expects ListenFree in `.build/language-music`, with its
normal runtime library/plugin paths available. The scripts use temporary
profiles, capture main/settings/editor views and 760×540 tool-app windows,
and verify QML load errors. `--language` and `--view` narrow the capture matrix;
`KOS_APP_BIN_DIR` and `LISTENFREE_BIN` can select installed binaries. Music captures require an X11/XWayland display.

`capture_widgets.py` uses a temporary platform service and the actual widget
items. It requires a Wayland desktop; `KOS_QUICKSHELL_BIN` can select a custom
Quickshell binary. Use `--size small` to check compact widgets. The render window
is temporary; widget settings are never written to the installed shell.
`KOS_SHELL_DIR` can select a staged or installed shell tree.

All captures cover Chinese, English, and French (English fallback), writing
PNGs and logs to `.build/language-qa`. Visually inspect the screenshots as well
as the log checks: text can be clipped without causing a QML warning.
