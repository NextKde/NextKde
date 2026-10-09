#pragma once
#include "online/radio_catalog.h"
#include "infrastructure/database/database.h"
#include <QDateTime>
#include <QFutureWatcher>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <functional>

namespace listenfree::qmlbridge {
class RadioService final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString provider READ provider WRITE setProvider NOTIFY changed)
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY changed)
    Q_PROPERTY(QString query READ query NOTIFY changed)
    Q_PROPERTY(QVariantList rows READ rows NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(int page READ page NOTIFY changed)
    Q_PROPERTY(bool hasMore READ hasMore NOTIFY changed)
    Q_PROPERTY(int total READ total NOTIFY changed)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY categoriesChanged)
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY changed)
    Q_PROPERTY(bool favoritesOnly READ favoritesOnly WRITE setFavoritesOnly NOTIFY changed)
    Q_PROPERTY(QVariantMap podcast READ podcast NOTIFY changed)
    Q_PROPERTY(int favoritesRevision READ favoritesRevision NOTIFY favoritesChanged)
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY favoritesChanged)
public:
    explicit RadioService(infrastructure::database::Database& db,QObject* parent=nullptr);
    QString provider()const{return provider_;} void setProvider(const QString&);
    QString mode()const{return state().mode;} void setMode(const QString&);
    QString query()const{return state().query;}
    QVariantList rows()const{return favoritesOnly_?favoriteRows_:state().rows;}
    bool busy()const{return busy_;} QString error()const{return error_;}
    int page()const{return favoritesOnly_?1:state().page;}bool hasMore()const{return !favoritesOnly_ && state().more;}
    int total()const{return favoritesOnly_?int(favoriteRows_.size()):state().total;}
    QVariantList categories()const;QString category()const{return state().category;}void setCategory(const QString&);
    bool favoritesOnly()const{return favoritesOnly_;}void setFavoritesOnly(bool);
    QVariantMap podcast()const{return favoritesOnly_?QVariantMap{}:state().podcast;}
    int favoritesRevision()const{return favoritesRevision_;}
    QVariantList favorites()const{return favorites_;}
    Q_INVOKABLE void activate();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void search(const QString& term);
    Q_INVOKABLE void goToPage(int page);
    Q_INVOKABLE void openPodcast(const QVariantMap& podcast);
    Q_INVOKABLE void closePodcast();
    Q_INVOKABLE bool isFavorite(const QVariantMap& row)const;
    Q_INVOKABLE void toggleFavorite(const QVariantMap& row);
signals:
    void changed();void categoriesChanged();void favoritesChanged();
private:
    struct State {
        QString query,category,mode{"broadcast"};QVariantList rows;QVariantMap podcast;
        int page{1},total{-1};bool more{},loaded{};QStringList cursors{"0|-1"};
        QHash<int,QVariantList> pages;
    };
    const State& state()const{return states_.constFind(provider_).value();}
    State& state(){return states_[provider_];}
    infrastructure::database::Database& db_;
    QString provider_{"icecast"},error_;QMap<QString,State> states_;
    QNetworkAccessManager network_;QPointer<QNetworkReply> reply_;
    quint64 generation_{};bool busy_{},activated_{},favoritesOnly_{};
    QVector<online::RadioStation> icecast_;QDateTime icecastFetched_;
    QFutureWatcher<QPair<QVector<online::RadioStation>,QString>> parser_;
    QVariantList favorites_,favoriteRows_,neteaseCategories_;
    QVariantList broadcastRows_;
    QString broadcastCategory_;
    int favoritesRevision_{};QStringList browserHosts_;int hostIndex_{};
    void cancel();void load(bool force=false);void loadIcecast(bool force);
    void filterIcecast();void loadBrowser(int attempt=0);void loadNetease();void showFavorites();
    void fetchBroadcast(const QString& lastId="0",const QString& score="-1");
    void filterBroadcast();
    void finish(QVariantList rows,int total,bool more);
    void get(const QUrl&,std::function<void(QByteArray,QString)> done,int limit=4*1024*1024);
};
}
