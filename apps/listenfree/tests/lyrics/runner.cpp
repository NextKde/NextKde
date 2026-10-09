#include <QtQuickTest/quicktest.h>
#include <QQmlEngine>
#include "spring_value.h"
#include "lyric_text_metrics.h"

class Setup : public QObject {
    Q_OBJECT
public slots:
    void applicationAvailable() {
        qmlRegisterType<listenfree::qmlbridge::SpringValue>("ListenFree.Native",1,0,"SpringValue");
        qmlRegisterType<listenfree::qmlbridge::LyricTextMetrics>("ListenFree.Native",1,0,"LyricTextMetrics");
    }
};
QUICK_TEST_MAIN_WITH_SETUP(listenfree_lyrics_tests, Setup)
#include "runner.moc"
