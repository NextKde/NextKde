#pragma once

#include <QQuick3DGeometry>
#include <QUrl>

class DepthMeshGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(QUrl depthPath READ depthPath WRITE setDepthPath NOTIFY depthPathChanged)
    Q_PROPERTY(QUrl mattePath READ mattePath WRITE setMattePath NOTIFY mattePathChanged)
    Q_PROPERTY(float imageZoom READ imageZoom WRITE setImageZoom NOTIFY imageZoomChanged)
    Q_PROPERTY(float outputAspect READ outputAspect WRITE setOutputAspect NOTIFY outputAspectChanged)
    Q_PROPERTY(float sourceAspect READ sourceAspect WRITE setSourceAspect NOTIFY sourceAspectChanged)
    Q_PROPERTY(float focusDistance READ focusDistance NOTIFY focusDistanceChanged)
    Q_PROPERTY(float backgroundDistance READ backgroundDistance NOTIFY backgroundDistanceChanged)
    Q_PROPERTY(bool valid READ valid NOTIFY validChanged)

public:
    explicit DepthMeshGeometry(QQuick3DObject *parent = nullptr);
    QUrl depthPath() const { return m_depthPath; }
    QUrl mattePath() const { return m_mattePath; }
    float imageZoom() const { return m_imageZoom; }
    float outputAspect() const { return m_outputAspect; }
    float sourceAspect() const { return m_sourceAspect; }
    float focusDistance() const { return m_focusDistance; }
    float backgroundDistance() const { return m_backgroundDistance; }
    bool valid() const { return m_valid; }
    void setDepthPath(const QUrl &path);
    void setMattePath(const QUrl &path);
    void setImageZoom(float zoom);
    void setOutputAspect(float aspect);
    void setSourceAspect(float aspect);

signals:
    void depthPathChanged();
    void mattePathChanged();
    void imageZoomChanged();
    void outputAspectChanged();
    void sourceAspectChanged();
    void focusDistanceChanged();
    void backgroundDistanceChanged();
    void validChanged();

private:
    void rebuild();
    void setValid(bool valid);
    QUrl m_depthPath;
    QUrl m_mattePath;
    float m_imageZoom = 1.16f;
    float m_outputAspect = 16.0f / 9.0f;
    float m_sourceAspect = 16.0f / 9.0f;
    float m_focusDistance = 2.5f;
    float m_backgroundDistance = 4.0f;
    bool m_valid = false;
};
