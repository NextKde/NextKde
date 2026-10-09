#include "qmlbridge/portable_session.h"
#include "online/platform_catalog.h"
#include "online/lyric_matching.h"
#include "online/lyric_sources.h"
#include <QDateTime>
#include "online/kuwo_lyrics.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <algorithm>
#include <QBuffer>
#include <QImageReader>
#include <QSaveFile>
#include <QFileInfo>
#include <QTimer>
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <QUuid>
#include <QtConcurrentRun>

namespace listenfree::qmlbridge {
void PortableSession::cancelMetadataMatch() {
    ++metadataArtworkGeneration_;
    if (metadataArtworkReply_) {
        auto reply = metadataArtworkReply_; metadataArtworkReply_ = nullptr; reply->abort();
    }
    metadataArtwork_.clear(); metadataArtworkIndex_ = -1; emit metadataArtworkChanged();
    if (metadataMatchReply_) {
        auto reply = metadataMatchReply_; metadataMatchReply_ = nullptr; reply->abort();
    }
    metadataMatchBusy_ = false;
    metadataCandidates_.clear(); metadataMatchError_.clear(); emit metadataMatchChanged();
}
void PortableSession::searchMetadataMatches(const QVariantMap& track, const QString& query, const QString& source) {
    cancelMetadataMatch();
    const auto term = (query.trimmed().isEmpty()
        ? track.value("title").toString() + " " + track.value("artist").toString() : query).trimmed();
    if (term.isEmpty() || (source != "wy" && source != "tx")) {
        metadataMatchError_ = QStringLiteral("请输入歌曲或艺术家，并选择搜索来源"); emit metadataMatchChanged(); return;
    }
    auto* reply = online::platformRequest(network_, source, "search", term);
    if (!reply) { metadataMatchError_ = QStringLiteral("信息来源不可用"); emit metadataMatchChanged(); return; }
    metadataMatchReply_ = reply; metadataMatchBusy_ = true; emit metadataMatchChanged();
    connect(reply, &QNetworkReply::finished, this, [this, reply, track, source] {
        reply->deleteLater(); if (metadataMatchReply_ != reply) return;
        metadataMatchReply_ = nullptr; metadataMatchBusy_ = false;
        if (reply->error() != QNetworkReply::NoError) metadataMatchError_ = QStringLiteral("搜索失败，请重试或切换来源");
        else {
            metadataCandidates_ = online::platformSongs(source, online::platformJson(reply->readAll()));
            for (auto& candidate : metadataCandidates_) {
                auto row = candidate.toMap(); row["score"] = online::lyricCandidateScore(track, row); candidate = row;
            }
            std::stable_sort(metadataCandidates_.begin(), metadataCandidates_.end(), [](const auto& a, const auto& b) {
                return a.toMap().value("score").toInt() > b.toMap().value("score").toInt();
            });
            if (metadataCandidates_.isEmpty()) metadataMatchError_ = QStringLiteral("没有找到结果，可简化关键词或切换来源");
        }
        emit metadataMatchChanged();
    });
}
QVariantMap PortableSession::metadataMatchValues(int index, const QStringList& fields) const {
    QVariantMap values;
    if (index < 0 || index >= metadataCandidates_.size()) return values;
    const auto candidate = metadataCandidates_[index].toMap();
    for (const auto& field : {QStringLiteral("title"), QStringLiteral("artist"), QStringLiteral("album")}) {
        const auto text = candidate.value(field).toString().trimmed();
        if (fields.contains(field) && !text.isEmpty()) values[field] = text;
    }
    if (fields.contains("artwork") && metadataArtworkIndex_ == index && !metadataArtwork_.value("url").toString().isEmpty())
        values["artwork"] = metadataArtwork_.value("url");
    return values;
}
void PortableSession::previewMetadataArtwork(int index) {
    const auto generation = ++metadataArtworkGeneration_;
    if (metadataArtworkReply_) {
        auto reply = metadataArtworkReply_; metadataArtworkReply_ = nullptr; reply->abort();
    }
    metadataArtworkIndex_ = index; metadataArtwork_.clear(); emit metadataArtworkChanged();
    if (index < 0 || index >= metadataCandidates_.size()) return;
    const auto candidate = metadataCandidates_[index].toMap();
    metadataArtwork_["busy"] = true; emit metadataArtworkChanged();
    const auto url = candidate.value("artwork").toUrl();
    if (!url.isEmpty()) { fetchMetadataArtwork(url, generation); return; }
    // NetEase search often omits the album picture; use the existing song detail request.
    if (candidate.value("source").toString() == "wy") {
        auto* reply = online::platformRequest(network_, "wy", "song", candidate.value("rid").toString());
        if (reply) {
            metadataArtworkReply_ = reply;
            connect(reply, &QNetworkReply::finished, this, [this, reply, generation] {
                reply->deleteLater(); if (generation != metadataArtworkGeneration_) return;
                metadataArtworkReply_ = nullptr;
                const auto rows = online::platformSongs("wy", online::platformJson(reply->readAll()));
                fetchMetadataArtwork(rows.isEmpty() ? QUrl{} : rows.first().toMap().value("artwork").toUrl(), generation);
            });
            return;
        }
    }
    fetchMetadataArtwork({}, generation);
}
void PortableSession::fetchMetadataArtwork(const QUrl& url, quint64 generation) {
    if (generation != metadataArtworkGeneration_) return;
    if (url.scheme() != "http" && url.scheme() != "https") {
        metadataArtwork_ = {{"error", "此版本未提供封面，保留当前封面"}}; emit metadataArtworkChanged(); return;
    }
    QNetworkRequest request(url); request.setTransferTimeout(12000);
    auto* reply = network_.get(request); metadataArtworkReply_ = reply;
    connect(reply, &QNetworkReply::downloadProgress, this, [reply](qint64 received, qint64 total) {
        if (qMax(received, total) > 12 * 1024 * 1024) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, generation] {
        reply->deleteLater(); if (generation != metadataArtworkGeneration_) return;
        metadataArtworkReply_ = nullptr;
        const auto bytes = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || bytes.isEmpty()) {
            metadataArtwork_ = {{"error", "封面加载失败，重新选择可重试"}}; emit metadataArtworkChanged(); return;
        }
        auto* watcher = new QFutureWatcher<QVariantMap>(this);
        connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher, generation] {
            const auto result = watcher->result(); watcher->deleteLater();
            if (generation != metadataArtworkGeneration_) return;
            metadataArtwork_ = result;
            const auto path = result.value("url").toUrl().toLocalFile();
            if (!path.isEmpty()) metadataArtworkFiles_.insert(path);
            emit metadataArtworkChanged();
        });
        watcher->setFuture(QtConcurrent::run([bytes, directory = metadataArtworkDirectory_] {
            QBuffer buffer; buffer.setData(bytes); buffer.open(QIODevice::ReadOnly);
            QImageReader reader(&buffer); reader.setAutoTransform(true);
            const auto size = reader.size();
            const QVariantMap failure{{"error", "封面图片无法读取，保留当前封面"}};
            if (!size.isValid() || qint64(size.width()) * size.height() > 64000000 || !directory->isValid()) return failure;
            if (size.width() > 1600 || size.height() > 1600) reader.setScaledSize(size.scaled(1600,1600,Qt::KeepAspectRatio));
            const auto image = reader.read();
            const auto path = directory->filePath(QUuid::createUuid().toString(QUuid::WithoutBraces) + ".jpg");
            if (image.isNull() || !image.save(path, "JPEG", 94)) return failure;
            return QVariantMap{{"url", QUrl::fromLocalFile(path).toString()}, {"width", image.width()}, {"height", image.height()}};
        }));
    });
}
namespace {
QString lyricKey(const QVariantMap& track) {
    return "lyrics.override."+QString::fromLatin1((track.value("localPath").toString().isEmpty()
        ? track.value("source").toString()+":"+track.value("rid",track.value("trackId")).toString()
        : track.value("localPath").toString()).toUtf8().toBase64(QByteArray::Base64UrlEncoding));
}
}
void PortableSession::cancelLyricMatch() { lyricSearch_.cancel(); }
void PortableSession::releaseLyricMatch() {
    lyricPreview_.clear(); lyricPreviewLines_.clear();
    lyricSearch_.release();
    emit lyricPreviewChanged();
}
QVariantMap PortableSession::lyricMatchSeed(const QVariantMap& track) const {
    auto seed=readTrackTags(track);
    const auto clean=[](QString text) {
        text=text.simplified();
        const QStringList placeholders{"未知歌曲","未知标题","未知艺术家","未知专辑","Unknown","Unknown Title","Unknown Artist","Unknown Album"};
        return placeholders.contains(text,Qt::CaseInsensitive)?QString{}:text;
    };
    for(const auto* field:{"title","artist","album"})seed[field]=clean(seed.value(field).toString());
    const auto title=seed.value("title").toString();
    const auto filename=QFileInfo(track.value("localPath").toString()).completeBaseName().trimmed();
    // A missing title tag must not leave the search field blank or search only
    // for a placeholder artist. Keep the actual filename, without its suffix.
    if(title.isEmpty())seed["title"]=filename;
    seed["queryFromFilename"]=title.isEmpty();
    seed["query"]=title.isEmpty()?filename:(title+" "+seed.value("artist").toString()).trimmed();
    return seed;
}
void PortableSession::searchLyricMatches(const QVariantMap& track,const QString& query,const QString& source) {
    const auto seed = query.trimmed().isEmpty() ? lyricMatchSeed(track) : track;
    const auto term = query.trimmed().isEmpty() ? seed.value("query").toString() : query;
    lyricSearch_.search(seed, term, source);
    lyricPreview_.clear(); lyricPreviewLines_.clear(); emit lyricPreviewChanged();
}
void PortableSession::previewLyricMatch(int index) {
    if(index<0 || index>=lyricSearch_.results().size())return;
    lyricPreview_=lyricSearch_.lyrics(index);lyricPreviewLines_=online::parseTimedLyrics(lyricPreview_);
    if(lyricPreviewLines_.isEmpty()&&!lyricPreview_.trimmed().isEmpty())
        for(const auto& line:lyricPreview_.split('\n'))if(!line.trimmed().isEmpty())lyricPreviewLines_.append(QVariantMap{{"text",line}});
    emit lyricPreviewChanged();
}
bool PortableSession::applyLyricMatch(const QVariantMap& track,const QString& lyrics) {
    const auto path=track.value("localPath").toString();
    if(!path.isEmpty()) {
        const QFileInfo media(path);
        if(!media.isFile()){emit notice("本地文件不存在");return false;}
        const auto previous=pendingEmbeddedLyrics_;
        pendingEmbeddedLyrics_[media.absoluteFilePath()]=lyrics;
        if(!persistEmbeddedLyrics()) { pendingEmbeddedLyrics_=previous;emit notice("歌词保存任务创建失败");return false; }
        embeddedLyricFailures_.remove(media.absoluteFilePath());
        if(QFileInfo(currentTrack().value("localPath").toString())==media)loadLyrics(path);
        pumpEmbeddedLyrics();
        return true;
    }
    if(!database_.setSetting(lyricKey(track),lyrics)){emit notice("歌词保存失败");return false;}
    if(lyricKey(currentTrack())==lyricKey(track)) {
        if(lyricsReply_){auto reply=lyricsReply_;lyricsReply_=nullptr;reply->abort();}
        lyrics_=online::parseTimedLyrics(lyrics);emit lyricsChanged();
    }
    return true;
}

void PortableSession::initializeEmbeddedLyrics() {
    pendingEmbeddedLyrics_=QJsonDocument::fromJson(QByteArray::fromStdString(database_.getSetting("lyrics.pendingEmbedded").value_or("{}"))).object().toVariantMap();
    connect(&embeddedLyricWrite_,&QFutureWatcher<QString>::finished,this,&PortableSession::finishEmbeddedLyrics);
    QTimer::singleShot(0,this,&PortableSession::pumpEmbeddedLyrics);
}
bool PortableSession::persistEmbeddedLyrics() {
    return database_.setSetting("lyrics.pendingEmbedded",QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(pendingEmbeddedLyrics_)).toJson(QJsonDocument::Compact)));
}
void PortableSession::pumpEmbeddedLyrics() {
    if(!embeddedLyricWritePath_.isEmpty())return;
    for(auto it=pendingEmbeddedLyrics_.cbegin();it!=pendingEmbeddedLyrics_.cend();++it) {
        const auto mixIndex=mixTargetIndex();
        if (mixIndex>=0 && QFileInfo(it.key())==QFileInfo(entries_.value(navigation_.track(mixIndex)).value("localPath").toString())) continue;
        if(embeddedLyricFailures_.contains(it.key()) || (!decoderLocalPath_.isEmpty() && QFileInfo(it.key())==QFileInfo(decoderLocalPath_)))continue;
        embeddedLyricWriteTags_=readTrackTags({{"localPath",it.key()}});
        embeddedLyricWritePath_=it.key();embeddedLyricWriteText_=it->toString();
        embeddedLyricWrite_.setFuture(QtConcurrent::run([path=embeddedLyricWritePath_,text=embeddedLyricWriteText_]() -> QString {
            // This path is released by the decoder; new playback waits for this job.
            TagLib::FileRef file(path.toStdWString().c_str(),false);
            if(file.isNull())return QStringLiteral("无法读取音频标签");
            auto properties=file.file()->properties();
            properties.replace("LYRICS",TagLib::StringList(TagLib::String(text.toStdString(),TagLib::String::UTF8)));
            if(file.file()->setProperties(properties).contains("LYRICS"))return QStringLiteral("文件不支持内嵌歌词");
            if(!file.save())return QStringLiteral("内嵌歌词保存失败，请检查文件权限");
            const QFileInfo info(path);const auto sidecar=info.absolutePath()+"/"+info.completeBaseName()+".lrc";
            if(QFileInfo::exists(sidecar)) {
                QSaveFile output(sidecar);const auto bytes=text.toUtf8();
                if(!output.open(QIODevice::WriteOnly)||output.write(bytes)!=bytes.size()||!output.commit())return QStringLiteral("已有 LRC 同步失败");
            }
            return {};
        }));
        return;
    }
}
void PortableSession::finishEmbeddedLyrics() {
    if(embeddedLyricWritePath_.isEmpty() || !embeddedLyricWrite_.isFinished())return;
    const auto path=std::exchange(embeddedLyricWritePath_,{});
    const auto text=std::exchange(embeddedLyricWriteText_,{});
    const auto error=embeddedLyricWrite_.result();
    embeddedLyricWriteTags_.clear();
    if(error.isEmpty()) {
        if(pendingEmbeddedLyrics_.value(path).toString()==text)pendingEmbeddedLyrics_.remove(path);
        persistEmbeddedLyrics();
    } else {
        embeddedLyricFailures_.insert(path);
        emit notice(error+QStringLiteral("；歌词已挂载，保存任务将在下次启动时重试"));
    }
    if(!stopped_ && QFileInfo(currentTrack().value("localPath").toString())==QFileInfo(path)) {
        if(loading_&&decoderLocalPath_.isEmpty())beginCurrent();
        else loadLyrics(path);
    }
    pumpEmbeddedLyrics();
}
}
