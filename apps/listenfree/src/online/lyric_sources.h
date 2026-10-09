#pragma once
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QVariantList>
#include <QVariantMap>

namespace listenfree::online {
QString lyricSourceName(const QString& source);
QNetworkReply* lyricSearchRequest(QNetworkAccessManager& network, const QString& source, const QVariantMap& track, const QString& query);
QVariantList lyricSearchResults(const QString& source, const QByteArray& response);
QNetworkReply* lyricFetchRequest(QNetworkAccessManager& network, const QString& source, const QVariantMap& candidate);
QString lyricResponse(const QString& source, const QByteArray& response);
QString decodeQrc(const QString& hex);
QString qrcWordLyrics(const QString& text);
QString krcLyricBundle(const QByteArray& bytes);
QString ttmlLyricBundle(const QByteArray& bytes);
}
