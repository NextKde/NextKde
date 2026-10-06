#include "kosdecoration.h"

#include <KPluginFactory>

// KWin's decoration bridge matches kwinrc's [org.kde.kdecoration2] library=
// key against this plugin's id, which is the installed file name. The group
// keeps its KDE 4/5 name even though KDecoration3 plugins install into an
// `org.kde.kdecoration3` directory -- the directory and the config group are
// not the same string (see tools/kosctl's kwin_decoration_group).
// kos_decoration. There is no separate theme= key for a compiled plugin.
K_PLUGIN_FACTORY_WITH_JSON(KosDecorationFactory,
                           "metadata.json",
                           registerPlugin<KOS::KosDecoration>();)

#include "main.moc"
