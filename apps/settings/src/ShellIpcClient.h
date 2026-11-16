#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QVector>
#include <functional>

// Shell transport only. Each request completes once on this object's thread.
// Empty payloads are valid replies; only a nonempty error indicates failure.
// Preferred session gets one retry, then each fallback gets one attempt.
class ShellIpcClient final : public QObject {
public:
    struct Result {
        QString payload;
        QString shellDirectory;
        QString error;
    };
    using Completion = std::function<void(const Result&)>;

    explicit ShellIpcClient(QObject* parent = nullptr);
    // Explicit launch parameters also allow isolated transport tests without
    // a running Shell or modifications to the user's session environment.
    ShellIpcClient(const QString& program, const QStringList& directories, int timeoutMs,
        QObject* parent = nullptr);
    void request(const QString& target, const QStringList& arguments, const QString& fallbackError,
        Completion completion);

    static QString installedShellDirectory();
    static bool isInstalledShellDirectory(const QString& shellPath);

private:
    static QStringList shellDirectories();
    static QStringList connectArgsFor(const QString& shellPath);
    static bool isIpcDiagnostic(const QString& reply);
    void startAttempt(const QString& target, const QStringList& arguments,
        const QString& fallbackError, const QStringList& directories, int index, int attempt,
        Completion completion);

    QString m_program;
    QStringList m_directories;
    int m_timeoutMs = 5000;
    // In-flight reads with identical target+arguments share one attempt: a
    // theme page instantiates several sections that each ask for the same
    // snapshot, and each QProcess spawn is a real fork of the shell. Writes
    // always carry distinct arguments, so they never collide on this key.
    struct InFlight {
        QStringList directories;
        int index = 0;
        int attempt = 0;
        QString fallbackError;
        QVector<Completion> completions;
    };
    QHash<QString, InFlight> m_inFlight;
};
