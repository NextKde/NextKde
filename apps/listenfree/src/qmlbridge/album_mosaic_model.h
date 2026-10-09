#pragma once

#include <QAbstractListModel>
#include <QRectF>
#include <QSet>
#include <QTimer>
#include <cmath>

// Only visible rectangles plus a one-cell guard band enter the scene graph.
// No image data, per-album geometry or unbounded world items are stored here.
class AlbumMosaicModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int albumCount READ albumCount WRITE setAlbumCount NOTIFY albumCountChanged)
    Q_PROPERTY(QRectF viewport READ viewport WRITE setViewport NOTIFY viewportChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QRectF expandedTile READ expandedTile WRITE setExpandedTile NOTIFY expandedTileChanged)
public:
    explicit AlbumMosaicModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}
    enum Role { Key = Qt::UserRole + 1, TileX, TileY, TileWidth, TileHeight, AlbumIndex };
    static constexpr int Unit = 144;
    int rowCount(const QModelIndex& parent = {}) const override { return parent.isValid() ? 0 : items_.size(); }
    int count() const { return items_.size(); }
    int albumCount() const { return albums_; }
    QRectF viewport() const { return viewport_; }
    QRectF expandedTile() const { return expandedTile_; }
    void setExpandedTile(const QRectF& value) {
        if(expandedTile_==value)return;
        expandedTile_=value; emit expandedTileChanged();
        // A QML delegate can close while a model removal is being delivered.
        // Rebuild after that transaction, retaining at most one extra chunk.
        QTimer::singleShot(0,this,[this]{region_={};rebuild();});
    }
    QHash<int,QByteArray> roleNames() const override {
        return {{Key,"tileKey"},{TileX,"tileX"},{TileY,"tileY"},{TileWidth,"tileWidth"},
                {TileHeight,"tileHeight"},{AlbumIndex,"albumIndex"}};
    }
    QVariant data(const QModelIndex& index, int role) const override {
        if (!index.isValid() || index.row() < 0 || index.row() >= items_.size()) return {};
        const auto& item = items_[index.row()];
        switch (role) {
        case Key: return item.key;
        case TileX: return item.rect.x();
        case TileY: return item.rect.y();
        case TileWidth: return item.rect.width();
        case TileHeight: return item.rect.height();
        case AlbumIndex: return item.album;
        default: return {};
        }
    }
    void setAlbumCount(int count) {
        count = qMax(0,count);
        if (albums_ == count) return;
        albums_ = count;
        beginResetModel(); items_.clear(); endResetModel();
        region_ = {}; rebuild(); emit albumCountChanged(); emit countChanged();
    }
    void setViewport(const QRectF& value) {
        if (viewport_ == value || !std::isfinite(value.x()) || !std::isfinite(value.y())) return;
        viewport_ = value; rebuild(); emit viewportChanged();
    }
signals:
    void albumCountChanged();
    void viewportChanged();
    void countChanged();
    void expandedTileChanged();
private:
    struct Tile { QString key; QRectF rect; int album; };
    void rebuild() {
        if (albums_ == 0 || viewport_.isEmpty()) return;
        const int left = int(std::floor(viewport_.left()/Unit))-1;
        const int top = int(std::floor(viewport_.top()/Unit))-1;
        const int right = int(std::ceil(viewport_.right()/Unit))+1;
        const int bottom = int(std::ceil(viewport_.bottom()/Unit))+1;
        const QRect region(left,top,right-left,bottom-top);
        if (region == region_) return;
        region_ = region;
        const QRectF guard(left*Unit,top*Unit,(right-left)*Unit,(bottom-top)*Unit);
        // A complete 4x4 partition: squares, landscape and portrait windows.
        static const QRect pattern[] = {{0,0,2,2},{2,0,2,1},{2,1,1,2},{3,1,1,1},
                                        {0,2,1,2},{1,2,1,1},{1,3,2,1},{3,2,1,2}};
        const int stride = qMax(1,int(std::ceil(std::sqrt(albums_/8.0))));
        QList<Tile> next;
        QSet<QString> wanted;
        QSet<QPair<int,int>> chunks;
        for (int cy=int(std::floor(top/4.0)); cy<=int(std::floor(bottom/4.0)); ++cy) {
            for (int cx=int(std::floor(left/4.0)); cx<=int(std::floor(right/4.0)); ++cx) chunks.insert({cx,cy});
        }
        const QPair<int,int> expandedChunk{int(std::floor(expandedTile_.x()/(Unit*4))),int(std::floor(expandedTile_.y()/(Unit*4)))};
        if(!expandedTile_.isEmpty())chunks.insert(expandedChunk);
        for(const auto& chunk:chunks) {
                const auto [cx,cy]=chunk;
                const bool pinned=!expandedTile_.isEmpty() && chunk==expandedChunk;
                for (int i=0;i<8;++i) {
                    const auto& p=pattern[i];
                    // Alternate chunk orientation without changing the partition.
                    const bool mirror = ((cx+cy)%2)!=0;
                    const QRectF rect((cx*4+(mirror ? 4-p.x()-p.width() : p.x()))*qreal(Unit),
                                      (cy*4+p.y())*qreal(Unit),p.width()*Unit-3,p.height()*Unit-3);
                    if (!pinned && !rect.intersects(guard)) continue;
                    const QString key=QString::number(cx)+":"+QString::number(cy)+":"+QString::number(i);
                    const qint64 ordinal=(qint64(cx)+qint64(cy)*stride)*8+i;
                    next.append({key,rect,int((ordinal%albums_+albums_)%albums_)});
                    wanted.insert(key);
                }
        }
        QSet<QString> retained;
        for(int i=items_.size()-1;i>=0;--i) {
            if(wanted.contains(items_[i].key)) retained.insert(items_[i].key);
            else {beginRemoveRows({},i,i);items_.removeAt(i);endRemoveRows();}
        }
        for(const auto& tile:next) if(!retained.contains(tile.key)) {
            const int row=items_.size();beginInsertRows({},row,row);items_.append(tile);endInsertRows();
        }
        emit countChanged();
    }
    int albums_ = 0;
    QRectF viewport_;
    QRectF expandedTile_;
    QRect region_;
    QList<Tile> items_;
};
