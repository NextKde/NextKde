#include "online/lyric_search.h"
#include "online/lyric_sources.h"
#include "online/lyric_matching.h"
#include <QtTest>
#include <QUrlQuery>
#include <cstring>
#include <functional>

using namespace listenfree::online;
namespace {
struct Response { QByteArray body; int delay{0}; int status{200}; QByteArray retryAfter{}; };
class Reply final : public QNetworkReply {
public:
    Reply(const QNetworkRequest& request, Response response, QObject* parent) : QNetworkReply(parent), bytes_(response.body) {
        setRequest(request); setUrl(request.url()); open(QIODevice::ReadOnly | QIODevice::Unbuffered);
        setAttribute(QNetworkRequest::HttpStatusCodeAttribute, response.status);
        if(!response.retryAfter.isEmpty())setRawHeader("Retry-After",response.retryAfter);
        if(response.delay >= 0) QTimer::singleShot(response.delay, this, [this, response] {
            if(isFinished())return;
            if(response.status>=400)setError(QNetworkReply::ContentAccessDenied,"synthetic HTTP failure");
            setFinished(true); emit readyRead(); emit finished();
        });
    }
    void abort() override {
        if(isFinished())return;
        setError(QNetworkReply::OperationCanceledError,"cancelled"); setFinished(true); emit finished();
    }
    qint64 bytesAvailable() const override { return isFinished() ? bytes_.size()-offset_+QIODevice::bytesAvailable() : 0; }
protected:
    qint64 readData(char* data, qint64 size) override {
        const auto count=qMin(size,qint64(bytes_.size()-offset_));
        if(count<=0)return -1;
        std::memcpy(data,bytes_.constData()+offset_,std::size_t(count));offset_+=count;return count;
    }
private:
    QByteArray bytes_; qint64 offset_{};
};
class Network final : public QNetworkAccessManager {
public:
    QList<QUrl> urls;
    std::function<Response(const QNetworkRequest&)> respond;
protected:
    QNetworkReply* createRequest(Operation, const QNetworkRequest& request, QIODevice*) override {
        urls.append(request.url()); return new Reply(request,respond(request),this);
    }
};
QByteArray lrcResult(const QString& title="Song", int id=1) {
    return QJsonDocument(QJsonArray{QJsonObject{{"id",id},{"trackName",title},{"artistName","Artist"},
        {"duration",180},{"syncedLyrics","[00:01.00]Synthetic test words\n[00:02.00]Another test line"}}}).toJson();
}
const QVariantMap track{{"title","Song"},{"artist","Artist"},{"durationMs",180000}};
}
class LyricSearchTests final : public QObject {
    Q_OBJECT
private slots:
    void progressiveResultsSurviveWholeDeadline() {
        Network network; network.respond=[](const auto& request) { return request.url().host()=="lrclib.net" ? Response{lrcResult(),1} : Response{{},-1}; };
        LyricSearch search(network,nullptr,1000,120);
        search.search(track,"Song Artist");
        QTRY_COMPARE_WITH_TIMEOUT(search.results().size(),1,100);
        QVERIFY(search.busy()); QVERIFY(!search.lyrics(0).isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),500);
        QCOMPARE(search.results().size(),1); QVERIFY(search.message().contains("暂不可用"));
    }
    void requestDeadlineRetriesAndFinishes() {
        Network network; network.respond=[](const auto&) { return Response{{},-1}; };
        LyricSearch search(network,nullptr,15,1500);
        search.search(track,"Song Artist","lrclib");
        QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),1200);
        QCOMPARE(network.urls.size(),2); QVERIFY(search.results().isEmpty());
    }
    void repeatedClicksAndCompletedSearchReuseSuccess() {
        Network network;network.respond=[](const auto&) { return Response{lrcResult(),30}; };
        LyricSearch search(network);
        for(int i=0;i<12;++i)search.search(track,"Song Artist","lrclib");
        QCOMPARE(network.urls.size(),1);
        QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),300);
        for(int i=0;i<12;++i) { search.search(track,"Song Artist","lrclib"); QVERIFY(!search.busy()); QCOMPARE(search.results().size(),1); QVERIFY(!search.lyrics(0).isEmpty()); }
        QCOMPARE(network.urls.size(),1);
    }
    void cancelledReplyCannotReplaceNewResults() {
        Network network;network.respond=[](const auto& request) {
            const auto title=QUrlQuery(request.url()).queryItemValue("track_name");
            return Response{lrcResult(title,title=="Song"?1:2),title=="Song"?200:1};
        };
        LyricSearch search(network);
        for(int i=0;i<8;++i) { search.search(track,"Song Artist","lrclib"); search.cancel(); QVERIFY(!search.busy()); }
        auto other=track;other["title"]="New Song";
        search.search(other,"New Song Artist","lrclib");
        QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),300);
        QCOMPARE(search.results().size(),1); QCOMPARE(search.results().first().toMap().value("title").toString(),QString("New Song"));
        QTest::qWait(230);
        QCOMPARE(search.results().size(),1);QCOMPARE(search.results().first().toMap().value("rid").toString(),QString("2"));
    }
    void releaseDropsSessionAndReusesBoundedSuccessCache() {
        Network network;network.respond=[](const auto&) { return Response{lrcResult(),1}; };
        LyricSearch search(network);
        search.search(track,"Song Artist","lrclib");
        QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),300);
        const auto accepted = search.lyrics(0);
        QVERIFY(!accepted.isEmpty());
        for(int i=0;i<10;++i) {
            QSignalSpy changed(&search,&LyricSearch::changed);
            search.release();
            QCOMPARE(changed.size(),1);
            QVERIFY(!search.busy());QVERIFY(search.results().isEmpty());QVERIFY(search.sources().isEmpty());
            QVERIFY(search.lyrics(0).isEmpty());
            search.release(); // Idempotent when already closed.
            search.search(track,"Song Artist","lrclib");
            QVERIFY(!search.busy());QCOMPARE(search.results().size(),1);QCOMPARE(search.lyrics(0),accepted);
        }
        QCOMPARE(network.urls.size(),1);
    }
    void stopRetainsResultsButReleaseInvalidatesPendingReplies() {
        Network network;network.respond=[](const auto& request) { return request.url().host()=="lrclib.net" ? Response{lrcResult(),1} : Response{{},200}; };
        LyricSearch search(network);
        search.search(track,"Song Artist");
        QTRY_COMPARE_WITH_TIMEOUT(search.results().size(),1,100);
        QVERIFY(search.busy());
        const auto accepted=search.lyrics(0);
        search.cancel();
        QVERIFY(!search.busy());QCOMPARE(search.results().size(),1);QCOMPARE(search.lyrics(0),accepted);
        search.release();
        QVERIFY(search.results().isEmpty());QVERIFY(search.sources().isEmpty());
        QTest::qWait(250);
        QVERIFY(search.results().isEmpty());QVERIFY(search.sources().isEmpty());QVERIFY(search.lyrics(0).isEmpty());
        search.search(track,"Song Artist","lrclib");
        QCOMPARE(search.results().size(),1);QCOMPARE(search.lyrics(0),accepted);
    }
    void releaseWhileBusyPublishesOnlyEmptySession() {
        Network network;network.respond=[](const auto&) { return Response{lrcResult(),200}; };
        LyricSearch search(network);
        search.search(track,"Song Artist","lrclib");
        QVERIFY(search.busy());
        QSignalSpy changed(&search,&LyricSearch::changed);
        search.release();
        QCOMPARE(changed.size(),1);QVERIFY(!search.busy());QVERIFY(search.sources().isEmpty());
        QTest::qWait(250);
        QCOMPARE(changed.size(),1);QVERIFY(search.results().isEmpty());
    }
    void emptyResponsesAreRetriedAndNotCached() {
        Network network;int requests=0;network.respond=[&](const auto&) { return Response{++requests<=2?QByteArray("[]"):lrcResult()}; };
        LyricSearch search(network);
        search.search(track,"Song Artist","lrclib");QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),1000);
        QVERIFY(search.results().isEmpty());QCOMPARE(requests,2);
        const QUrlQuery first(network.urls[0]),second(network.urls[1]);
        QCOMPARE(first.queryItemValue("artist_name"),QString("Artist"));QVERIFY(!second.hasQueryItem("artist_name"));
        search.search(track,"Song Artist","lrclib");QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),300);
        QCOMPARE(search.results().size(),1);QCOMPARE(requests,3);
    }
    void rateLimitDoesNotLeaveBusyOrGetHammered() {
        Network network;network.respond=[](const auto&) { return Response{{},0,429,"2"}; };
        LyricSearch search(network);
        search.search(track,"Song Artist","lrclib");QTRY_VERIFY_WITH_TIMEOUT(!search.busy(),1000);
        QCOMPARE(network.urls.size(),1);
        search.release(); // Closing the dialog must not defeat provider backoff.
        search.search(track,"Song Artist","lrclib");QVERIFY(!search.busy());QCOMPARE(network.urls.size(),1);
        QVERIFY(search.sources().first().toMap().value("detail").toString().contains("限流"));
    }
    void sparseMetadataAndAlternativeTitlesRemainCandidates() {
        auto sparse=track;sparse.remove("durationMs");sparse.remove("artist");
        auto wrong=track;wrong["title"]="Entirely unrelated";
        auto wrongArtist=track;wrongArtist["artist"]="Unrelated performer";
        auto alias=track;alias["title"]="Localized title";alias["titleAliases"]=QStringList{"Song","Localized title"};
        const auto ranked=rankLyricCandidates(track,"Song Artist",{track,sparse,wrong,wrongArtist,alias});
        QCOMPARE(ranked.size(),3);
        QCOMPARE(rankLyricCandidates(track,"Artist Song",{track}).size(),1);
        QCOMPARE(rankLyricCandidates(track,"Completely New",{QVariantMap{{"title","Completely New"},{"durationMs",800000}}}).size(),1);
        auto collaboration=track;collaboration["artist"]="Guest / Artist";
        QCOMPARE(rankLyricCandidates(track,"Song Artist",{collaboration}).size(),1);
    }
    void communityApiRetainsIdentityAndTtml() {
        const QJsonObject item{{"id",6904357435025915LL},{"filename","test.ttml"},
            {"musicNames",QJsonArray{"Song","歌曲"}},{"artistNames",QJsonArray{"Artist"}},{"authorUsernames",QJsonArray{"Contributor"}}};
        const auto bytes=QJsonDocument(QJsonObject{{"status",200},{"data",QJsonObject{{"items",QJsonArray{item}}}}}).toJson();
        const auto rows=lyricSearchResults("amll",bytes);QCOMPARE(rows.size(),1);
        QCOMPARE(rows.first().toMap().value("rid").toString(),QString("6904357435025915"));
        QVERIFY(rows.first().toMap().value("sourceUrl").toString().endsWith("raw-lyrics/test.ttml"));
        Network network;network.respond=[](const auto&) { return Response{{},-1}; };
        auto* reply=lyricFetchRequest(network,"amll",rows.first().toMap());
        QCOMPARE(reply->url().host(),QString("api.amll.dev"));QCOMPARE(QUrlQuery(reply->url()).queryItemValue("id"),QString("6904357435025915"));reply->abort();reply->deleteLater();
        QFile fixture(QFINDTESTDATA("fixtures/lyrics/synthetic.ttml"));QVERIFY(fixture.open(QIODevice::ReadOnly));
        const auto response=QJsonDocument(QJsonObject{{"data",QJsonObject{{"lyrics",QString::fromUtf8(fixture.readAll())}}}}).toJson();
        const auto features=matchedLyricFeatures(lyricResponse("amll",response));
        QVERIFY(features.contains("逐字"));QVERIFY(features.contains("翻译"));QVERIFY(features.contains("罗马音"));
    }
};
QTEST_GUILESS_MAIN(LyricSearchTests)
#include "lyric_search_tests.moc"
