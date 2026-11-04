#pragma once

#include <QElapsedTimer>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

// 「我的笔记」扩展控制器。
//
// 与「灵动岛」遵循同一套约定：源码在 NextKde/Notes，安装时用 install.sh 构建到
// ~/.local/share/nextkde-notes/current，并写 installed.json 标记。区别在于运行状态
// 由 D-Bus 上的 org.nextkde.Notes 判断——笔记进程自己注册这个总线名，因此
// 面板能“自动检测”它是被开启、还是已经退出（包括用户从悬浮球/托盘里退出）。
class NotesExtension final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)

public:
    explicit NotesExtension(const QString& sourceDirectory, QObject* parent = nullptr);
    ~NotesExtension() override;

    QVariantMap state() const { return m_state; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install();
    Q_INVOKABLE void launch();
    Q_INVOKABLE void quit();
    Q_INVOKABLE void uninstall();
    Q_INVOKABLE void openMainWindow();

signals:
    void changed();

private:
    void setFlag(const QString& key, const QVariant& value);
    void finishInstall(int exitCode, QProcess::ExitStatus status);
    void reloadMarker();
    void syncRunning();
    void fail(const QString& code);
    QString resolveSource() const;
    QString dataDirectory() const;
    QString markerPath() const;
    QString binaryPath() const;
    bool serviceRegistered() const;

    QVariantMap m_state;
    QString m_source;
    QProcess m_install;
    QElapsedTimer m_elapsed;
    QString m_logPath;
    QTimer m_poll;
    bool m_installing = false;
};
