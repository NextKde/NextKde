#pragma once

#include <QObject>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QJsonObject>
#include <QJsonArray>
#include <QStringList>
#include <QPointer>

namespace KosPlatform {

class KimpanelBridge;

class ImpanelAdaptor final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.impanel")

public:
    explicit ImpanelAdaptor(KimpanelBridge *parent);

signals:
    void PanelCreated();
    void PanelCreated2();
    void SelectCandidate(int index);
    void LookupTablePageUp();
    void LookupTablePageDown();
    void MovePreeditCaret(int pos);
    void TriggerProperty(const QString &key);
    void ReloadConfig();
    void Configure();
    void Restart();
};

class Impanel2Adaptor final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.impanel2")

public:
    explicit Impanel2Adaptor(KimpanelBridge *parent);

public slots:
    void SetSpotRect(int x, int y, int w, int h);
    void SetRelativeSpotRect(int x, int y, int w, int h);
    void SetRelativeSpotRectV2(int x, int y, int w, int h, double scale);
    void SetLookupTable(const QStringList &labels, const QStringList &texts,
                        const QStringList &attrs, bool hasPrev, bool hasNext,
                        int cursor, int layout);

signals:
    void PanelCreated2();
};

class KimpanelBridge final : public QObject {
    Q_OBJECT

public:
    explicit KimpanelBridge(QObject *parent = nullptr);
    ~KimpanelBridge() override;

    bool isUserEnabled() const { return m_userEnabled; }
    bool isTakeoverActive() const { return m_takeoverActive; }
    bool setUserEnabled(bool enabled);
    void setShellConnected(bool connected);
    void syncTakeoverState();
    void reassertTakeover();

    static QString configPath();
    static bool loadPersistedEnabled();
    static bool savePersistedEnabled(bool enabled);

    QJsonObject currentState() const;

    // Control actions triggered by platform client
    void selectCandidate(int index);
    void pageUp();
    void pageDown();
    void triggerProperty(const QString &property);
    void configure();
    void reloadConfig();

    void setActiveWindowId(const QString &windowId);

signals:
    void stateChanged(const QJsonObject &state);
    void menuRequested(const QJsonObject &menu);

public slots:
    // Slots called by adaptors
    void handleSetSpotRect(int x, int y, int w, int h);
    void handleSetRelativeSpotRect(int x, int y, int w, int h);
    void handleSetRelativeSpotRectV2(int x, int y, int w, int h, double scale);
    void handleSetLookupTable(const QStringList &labels, const QStringList &texts,
                              const QStringList &attrs, bool hasPrev, bool hasNext,
                              int cursor, int layout);

private slots:
    // Slots connected to /kimpanel on org.kde.kimpanel.inputmethod
    void onShowAux(bool visible);
    void onShowPreedit(bool visible);
    void onShowLookupTable(bool visible);
    void onUpdateLookupTableCursor(int cursor);
    void onUpdatePreeditCaret(int caret);
    void onUpdatePreeditText(const QString &text, const QString &attr);
    void onUpdateAux(const QString &text, const QString &attr);
    void onUpdateSpotLocation(int x, int y);
    void onUpdateScreen(int screen);
    void onEnable(bool enabled);
    void onRegisterProperties(const QStringList &props);
    void onUpdateProperty(const QString &prop);
    void onRemoveProperty(const QString &prop);
    void onExecMenu(const QStringList &items);
    void onExecDialog(const QString &dialog);

private:
    void setupDbusListeners();
    void teardownDbusListeners();
    void queryKWinCaret();
    void notifyState();
    void parseAndStoreProperty(const QString &prop);

    bool acquireTakeover();
    void releaseTakeover();
    bool backupOriginalFcitxAddons();
    bool setFcitxAddons(bool classicUi, bool kimpanel);
    bool restartFcitx();
    bool waitForPanelAdapter();
    bool saveRecoveryState();
    void recoverOriginalFcitxAddons();
    QString recoveryPath() const;

    ImpanelAdaptor *m_adaptor = nullptr;
    Impanel2Adaptor *m_adaptor2 = nullptr;

    bool m_userEnabled = false;
    bool m_shellConnected = false;
    bool m_takeoverActive = false;
    bool m_registeredBus = false;
    bool m_transitioning = false;
    bool m_destroying = false;
    bool m_addonsChanged = false;
    QString m_error;

    bool m_hasOriginalAddonState = false;
    bool m_origClassicUiEnabled = true;
    bool m_origKimpanelEnabled = false;

    quint64 m_kwinCaretSerial = 0;

    // State cache
    bool m_imEnabled = true;
    bool m_lookupVisible = false;
    bool m_preeditVisible = false;
    QString m_preeditText;
    int m_preeditCaret = 0;
    bool m_auxVisible = false;
    QString m_auxText;
    int m_cursorIndex = -1;
    bool m_hasPrev = false;
    bool m_hasNext = false;
    int m_layout = 0;
    QJsonArray m_candidates;

    // Spot coordinates
    int m_spotX = 0;
    int m_spotY = 0;
    int m_spotWidth = 0;
    int m_spotHeight = 0;
    double m_spotScale = 1.0;
    QString m_spotMode = QStringLiteral("absolute");

    // Caret coordinates from KWin
    QJsonObject m_kwinCaret;

    // Properties
    QString m_imLabel = QStringLiteral("中");
    QString m_imIcon = QStringLiteral("fcitx-rime");
    QString m_imName = QStringLiteral("中州韵");
    QJsonArray m_properties;
    QString m_activeWindowId;
};

} // namespace KosPlatform
