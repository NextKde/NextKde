// SPDX-License-Identifier: GPL-2.0-or-later
#include "../windoweffectpolicy.h"

#include <QString>
#include <cstdlib>
#include <iostream>

int main()
{
    struct TestCase {
        QStringView windowClass;
        bool excluded;
    };
    const TestCase cases[] = {
        {u"mime", true},
        {u"Mime", true},
        {u"MIME", true},
        {u"mime.quark_cloud_drive", true},
        {u"mime.Autodesk.AutoCAD.2026", true},
        {u"mime.Company-App_2026", true},
        {u"mime mime", true},
        {u"instance mime", true},
        {u"mime instance", true},
        {u"mime.app mime.app", true},
        {u"  instance\tMiMe.App\n", true},
        {u"", false},
        {u" \t\n", false},
        {u"mime.", false},
        {u"mimetype-editor", false},
        {u"mime-editor", false},
        {u"mime_helper", false},
        {u"org.example.mime", false},
        {u"org.example.mime.app", false},
        {u"notmime.app", false},
        {u"quark_cloud_drive", false},
        {u"acad.exe", false},
        {u"org.kde.kate", false},
        {u"quickshell quickshell", false},
        {u"code code", false},
    };
    for (const auto &test : cases) {
        if (KOS::keepsClientAppearance(test.windowClass) != test.excluded) {
            std::cerr << "wrong appearance ownership for: "
                      << test.windowClass.toString().toStdString() << '\n';
            return EXIT_FAILURE;
        }
    }
    std::cout << "Mime appearance ownership: base ID, guest IDs, WM_CLASS tokens "
                 "and unrelated applications passed\n";
    return EXIT_SUCCESS;
}
