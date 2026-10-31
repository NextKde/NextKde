#include <QtQuickTest/quicktest.h>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(Kos_DemoPlugin)

int main(int argc, char **argv)
{
    return quick_test_main(argc, argv, "kos-shared-motion", nullptr);
}
