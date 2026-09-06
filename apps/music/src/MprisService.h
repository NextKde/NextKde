#pragma once

#include <QObject>
#include <QVariantMap>

class MusicController;

class MprisService : public QObject {
    Q_OBJECT

public:
    explicit MprisService(MusicController *controller, QObject *parent = nullptr);
    ~MprisService() override;

    bool registered() const;

private:
    void publishPlayerProperties(const QVariantMap &properties) const;

    bool m_objectRegistered = false;
    bool m_registered = false;
};
