#pragma once
#include <QQuickItem>
#include <QAbstractListModel>
#include <QMatrix4x4>
#include <QColor>
#include <QVariantList>
#include <QPointer>
#include <QVector3D>
#include <QImage>

// Native adaptations of Folia's scene/timing functions. Upstream 71c5705,
// AGPL-3.0; provenance and renderer trade-offs: docs/research/immersive-native.md.
struct FoliaPose {
    qreal x=0,y=0,scale=1,rotation=0,alpha=1,light=0,ghost=0,lift=0,ghostScale=1;
    qreal pitch=0,yaw=0,depth=0,defocus=0;
    QColor color=QColor("#faf7f2");
};
class FoliaNodeModel final : public QAbstractListModel {
    Q_OBJECT
public:
    using QAbstractListModel::QAbstractListModel;
    int rowCount(const QModelIndex& parent={}) const override{return parent.isValid()?0:rows_.size();}
    QVariant data(const QModelIndex& index,int role) const override{return role==Qt::UserRole&&index.isValid()?rows_.value(index.row()):QVariant{};}
    QHash<int,QByteArray> roleNames() const override{return {{Qt::UserRole,"node"}};}
    void sync(const QVariantList& rows);
private: QVariantList rows_;
};
class FoliaScene : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QVariantList lyrics READ lyrics WRITE setLyrics NOTIFY lyricsChanged)
    Q_PROPERTY(QString style READ style WRITE setStyle NOTIFY styleChanged)
    Q_PROPERTY(QString seed READ seed WRITE setSeed NOTIFY lyricsChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY lyricsChanged)
    Q_PROPERTY(qreal position READ position WRITE setPosition NOTIFY frameChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion WRITE setReducedMotion NOTIFY frameChanged)
    Q_PROPERTY(bool wordTiming READ wordTiming WRITE setWordTiming NOTIFY frameChanged)
    Q_PROPERTY(qreal energy READ energy WRITE setEnergy NOTIFY frameChanged)
    Q_PROPERTY(QColor accentColor READ accentColor WRITE setAccentColor NOTIFY accentColorChanged)
    Q_PROPERTY(QVariantMap composition READ composition WRITE setComposition NOTIFY compositionChanged)
    Q_PROPERTY(QVariantList layoutUnits READ layoutUnits NOTIFY currentChanged)
    Q_PROPERTY(QVariantList placements READ placements WRITE setPlacements NOTIFY placementsChanged)
    Q_PROPERTY(QObject* model READ model CONSTANT)
    Q_PROPERTY(int lineIndex READ lineIndex NOTIFY currentChanged)
    Q_PROPERTY(QString translation READ translation NOTIFY currentChanged)
    Q_PROPERTY(QString shotName READ shotName NOTIFY currentChanged)
public:
    explicit FoliaScene(QQuickItem* parent=nullptr);
    QVariantList lyrics()const{return lyrics_;} void setLyrics(const QVariantList& value);
    QString style()const{return style_;}void setStyle(const QString& value);
    QString seed()const{return seed_;}void setSeed(const QString& value);
    QString fontFamily()const{return family_;}void setFontFamily(const QString& value);
    qreal position()const{return position_;}void setPosition(qreal value);
    bool reducedMotion()const{return reduced_;}void setReducedMotion(bool value);
    bool wordTiming()const{return timed_;}void setWordTiming(bool value);
    qreal energy()const{return energy_;}void setEnergy(qreal value);
    QColor accentColor()const{return accent_;}void setAccentColor(const QColor& value);
    static QColor accentFromImage(const QImage& image);
    Q_INVOKABLE void sampleArtwork(QQuickItem* source);
    Q_INVOKABLE void resetArtworkAccent();
    QVariantMap composition()const{return composition_;}void setComposition(const QVariantMap& value){if(composition_==value)return;composition_=value;compile();emit compositionChanged();}
    QVariantList layoutUnits()const;QVariantList placements()const{return placements_;}
    void setPlacements(const QVariantList& value){if(placements_==value)return;placements_=value;emit placementsChanged();emit frameChanged();}
    QObject* model(){return &model_;}int lineIndex()const{return current_;}
    QString translation()const;QString shotName()const;
    FoliaPose pose(const QVariantMap& node) const;
    Q_INVOKABLE QVariantMap inspectPose(int line,int glyph) const;
    Q_INVOKABLE QVariantMap inspectCamera() const;
signals:
    void lyricsChanged();void styleChanged();void frameChanged();void currentChanged();void compositionChanged();void placementsChanged();void accentColorChanged();
protected: void geometryChange(const QRectF& now,const QRectF& old) override;
private:
    friend class FoliaDecorItem;
    struct Glyph {QString text;qreal x=0,y=0,w=0,start=0,end=0;int ordinal=0,row=0,group=0;bool timed=false;};
    struct Line {QString text,translation;qreal start=0,end=0,w=0,h=0,font=48;bool chorus=false;QVector<Glyph> glyphs;QVector3D origin,right,up,forward;int shot=0;};
    void compile();void rebuildWindow();qreal cameraIndex()const;qreal progress(int line)const;
    QVariantMap nodeFor(int line,int glyph,int kind=0)const;
    FoliaPose dioramaPose(const QVariantMap& node)const;
    void updateDioramaCamera();
    qreal dioramaUnit(const Line& line)const;
    struct Camera {QVector3D eye,right,down,forward;QMatrix4x4 view;qreal focal=1,distance=5.2;bool valid=false;} camera_;
    unsigned geometryRevision_=0;
    QVariantList lyrics_;QVector<Line> lines_;FoliaNodeModel model_;
    QVariantMap composition_;
    QVariantList placements_;
    QString style_="classic",seed_,family_="Microsoft YaHei UI";
    qreal position_=0,energy_=0;int current_=-1;bool reduced_=false,timed_=true;
    QColor accent_=QColor("#ddd9d3");unsigned artworkGeneration_=0;
};
class FoliaPlaneTransform final : public QQuickTransform {
public:
    using QQuickTransform::QQuickTransform;
    void setPlane(qreal pitch,qreal yaw,qreal w,qreal h);
    void applyTo(QMatrix4x4* matrix) const override{*matrix *=matrix_;}
private:QMatrix4x4 matrix_;
};
class FoliaNodeItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(FoliaScene* scene READ scene WRITE setScene NOTIFY sceneChanged)
    Q_PROPERTY(QVariantMap node READ node WRITE setNode NOTIFY nodeChanged)
    Q_PROPERTY(qreal highlight READ highlight NOTIFY paintChanged)
    Q_PROPERTY(qreal ghostOpacity READ ghostOpacity NOTIFY paintChanged)
    Q_PROPERTY(qreal ghostLift READ ghostLift NOTIFY paintChanged)
    Q_PROPERTY(qreal ghostScale READ ghostScale NOTIFY paintChanged)
    Q_PROPERTY(qreal defocus READ defocus NOTIFY paintChanged)
    Q_PROPERTY(QColor ink READ ink NOTIFY paintChanged)
public:
    explicit FoliaNodeItem(QQuickItem* parent=nullptr);
    FoliaScene* scene()const{return scene_;}void setScene(FoliaScene* scene);
    QVariantMap node()const{return node_;}void setNode(const QVariantMap& node);
    qreal highlight()const{return paint_.light;}qreal ghostOpacity()const{return paint_.ghost;}
    qreal ghostLift()const{return paint_.lift;}qreal ghostScale()const{return paint_.ghostScale;}
    qreal defocus()const{return paint_.defocus;}
    QColor ink()const{return paint_.color;}
signals:void sceneChanged();void nodeChanged();void paintChanged();
private:void advance();QPointer<FoliaScene> scene_;QVariantMap node_;FoliaPose paint_;FoliaPlaneTransform plane_;
};
class ImmersiveSpectrumItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QVariantList bands READ bands WRITE setBands NOTIFY bandsChanged)
public:
    explicit ImmersiveSpectrumItem(QQuickItem* parent=nullptr):QQuickItem(parent){setFlag(ItemHasContents);}
    QVariantList bands()const{return bands_;}void setBands(const QVariantList& bands){bands_=bands;update();emit bandsChanged();}
signals:void bandsChanged();
protected:QSGNode* updatePaintNode(QSGNode* old,UpdatePaintNodeData*)override;
    void geometryChange(const QRectF& now,const QRectF& old) override{QQuickItem::geometryChange(now,old);update();}
private:QVariantList bands_;
};
class FoliaDecorItem : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(FoliaScene* scene READ scene WRITE setScene NOTIFY sceneChanged)
public:
    explicit FoliaDecorItem(QQuickItem* parent=nullptr):QQuickItem(parent){setFlag(ItemHasContents);}
    FoliaScene* scene()const{return scene_;}void setScene(FoliaScene* scene);
signals:void sceneChanged();
protected:QSGNode* updatePaintNode(QSGNode* old,UpdatePaintNodeData*)override;
private:QPointer<FoliaScene> scene_;
};
