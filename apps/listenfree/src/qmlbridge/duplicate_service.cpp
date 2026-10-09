#include "duplicate_service.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QtConcurrent/QtConcurrentRun>
#include <algorithm>

namespace listenfree::qmlbridge {
namespace {
QString digest(const QString& path,const std::shared_ptr<std::atomic_bool>& cancel) {
    QFile file(path); QCryptographicHash hash(QCryptographicHash::Sha256);
    if(!file.open(QIODevice::ReadOnly))return {};
    while(!file.atEnd()) {
        if(cancel->load())return {};
        const auto bytes=file.read(1024*1024);
        if(bytes.isEmpty() && file.error()!=QFile::NoError)return {};
        hash.addData(bytes);
    }
    return QString::fromLatin1(hash.result().toHex());
}
bool signature(const QVariantMap& item) {
    const auto path=item.value("path").toString();const QFileInfo file(path);
    return file.isFile() && !file.isSymLink() && file.canonicalFilePath().compare(path,Qt::CaseInsensitive)==0 &&
        file.size()==item.value("size").toLongLong() && file.lastModified().toMSecsSinceEpoch()==item.value("modified").toLongLong();
}
}
DuplicateService::DuplicateService(const QString& path,LibraryController& library,QObject* parent)
    :QObject(parent),databasePath_(path),library_(library) {
    connect(&work_,&QFutureWatcher<QVariantMap>::finished,this,[this] {
        auto future=work_.future();
        const auto result=future.takeResult(); busy_=false;library_.endMaintenance();
        if(merging_) {
            groups_.clear(); emit merged(result.value("redirects").toList());
            report_=tr("已合并 %1 个文件。\n%2").arg(result.value("redirects").toList().size()).arg(result.value("errors").toStringList().join('\n'));
            if(cancelled_->load())report_+=tr("\n已取消，已完成的处理保留。");
            emit changed();emit notice(report_);return;
        }
        groups_=result.value("groups").toList();
        if(cancelled_->load()){groups_.clear();report_=tr("分析已取消。");emit changed();return;}
        QStringList lines; qint64 bytes=0;int count=0;
        for(const auto& value:groups_) {
            const auto group=value.toMap(); const auto keep=group.value("keeper").toMap();
            lines.append(tr("保留：%1").arg(keep.value("path").toString()));
            lines.append("SHA-256: "+group.value("hash").toString());
            for(const auto& duplicate:group.value("duplicates").toList()) {
                const auto row=duplicate.toMap();++count;bytes+=row.value("size").toLongLong();
                lines.append(tr("重复：%1").arg(row.value("path").toString()));
            }
        }
        report_=tr("发现 %1 组、%2 个重复文件，可释放 %3 MiB。\n").arg(groups_.size()).arg(count).arg(bytes/1048576.0,0,'f',2)+lines.join('\n');
        report_+=tr("\n受影响的队列和歌单引用：%1").arg(result.value("references").toInt());
        const auto errors=result.value("errors").toStringList();
        if(!errors.isEmpty())report_+='\n'+errors.join('\n');
        emit changed();emit analysisReady();
    });
}
DuplicateService::~DuplicateService(){cancel();work_.waitForFinished();}
bool DuplicateService::unchanged(const QVariantMap& file,const QString& hash,const std::shared_ptr<std::atomic_bool>& cancel) {
    return signature(file) && digest(file.value("path").toString(),cancel)==hash && signature(file);
}
QVariantMap DuplicateService::analyzeFiles(const QVariantList& files,const std::shared_ptr<std::atomic_bool>& cancel) {
    QMap<qint64,QVariantList> sizes; QStringList errors;
    for(const auto& value:files) {
        auto item=value.toMap();const QFileInfo file(item.value("path").toString());
        if(!file.isFile() || file.isSymLink())continue;
        item["path"]=file.canonicalFilePath();item["size"]=file.size();item["modified"]=file.lastModified().toMSecsSinceEpoch();
        sizes[file.size()].append(item);
    }
    QVariantList groups;
    for(const auto& candidates:sizes) {
        if(candidates.size()<2)continue;
        QMap<QString,QVariantList> hashes;
        for(const auto& candidate:candidates) {
            if(cancel->load())return {};
            const auto item=candidate.toMap();const auto hash=digest(item.value("path").toString(),cancel);
            if(hash.isEmpty() || !signature(item)){errors.append(tr("跳过无法读取或已变化的文件：%1").arg(item.value("path").toString()));continue;}
            hashes[hash].append(item);
        }
        for(auto it=hashes.begin();it!=hashes.end();++it) {
            auto items=it.value();if(items.size()<2)continue;
            std::sort(items.begin(),items.end(),[](const QVariant& a,const QVariant& b){
                const auto x=a.toMap().value("path").toString(),y=b.toMap().value("path").toString();
                return x.size()!=y.size()?x.size()<y.size():QString::compare(x,y,Qt::CaseSensitive)<0;
            });
            const auto keeper=items.takeFirst();groups.append(QVariantMap{{"keeper",keeper},{"duplicates",items},{"hash",it.key()}});
        }
    }
    return {{"groups",groups},{"errors",errors}};
}
void DuplicateService::analyze() {
    if(busy_)return;
    if(!library_.beginMaintenance()){emit notice(tr("请先结束资料库扫描，再检查重复文件。"));return;}
    busy_=true;merging_=false;groups_.clear();report_=tr("正在按大小和完整哈希分析…");
    cancelled_=std::make_shared<std::atomic_bool>(false);emit changed();
    work_.setFuture(QtConcurrent::run([path=databasePath_,cancel=cancelled_] {
        infrastructure::database::Database db;
        if(!db.openExisting(path))return QVariantMap{{"errors",QStringList{tr("无法打开资料库。")}}};
        QVariantList files;
        for(const auto& track:db.loadTracks())if(track.localPath)files.append(QVariantMap{{"id",QString::fromStdString(track.id.value())},{"path",QString::fromStdString(*track.localPath)}});
        auto result=analyzeFiles(files,cancel);QSet<QString> paths;
        for(const auto& group:result.value("groups").toList())for(const auto& item:group.toMap().value("duplicates").toList())paths.insert(item.toMap().value("path").toString().toCaseFolded());
        const auto count=[&](auto&& self,const QJsonValue& value)->int {
            int total=0;
            if(value.isArray())for(const auto& child:value.toArray())total+=self(self,child);
            else if(value.isObject()){
                const auto object=value.toObject();if(paths.contains(QDir::fromNativeSeparators(object.value("localPath").toString()).toCaseFolded()))++total;
                for(auto it=object.begin();it!=object.end();++it)if(it.value().isArray()||it.value().isObject())total+=self(self,it.value());
            }
            return total;
        };
        int references=0;for(const auto& key:{QString("portable.queue"),QString("collections.v1")}) {
            const auto document=QJsonDocument::fromJson(QByteArray::fromStdString(db.getSetting(key).value_or("{}")));
            references+=count(count,document.isArray()?QJsonValue(document.array()):QJsonValue(document.object()));
        }
        result["references"]=references;return result;
    }));
}
void DuplicateService::cancel(){if(cancelled_)cancelled_->store(true);}
void DuplicateService::merge(bool recycle) {
    if(busy_ || groups_.isEmpty())return;
    if(!library_.beginMaintenance()){emit notice(tr("请先结束资料库扫描。"));return;}
    busy_=true;merging_=true;cancelled_=std::make_shared<std::atomic_bool>(false);report_=tr("正在验证并合并重复文件…");emit changed();
    if(recycle)emit mergeStarting(groups_);
    work_.setFuture(QtConcurrent::run([path=databasePath_,groups=groups_,cancel=cancelled_,recycle] {
        infrastructure::database::Database db;QVariantList redirects;QStringList errors;
        if(!db.openExisting(path))return QVariantMap{{"errors",QStringList{tr("无法打开资料库。")}}};
        for(const auto& value:groups) {
            const auto group=value.toMap();const auto keep=group.value("keeper").toMap();const auto hash=group.value("hash").toString();
            for(const auto& duplicate:group.value("duplicates").toList()) {
                if(cancel->load())break;
                const auto row=duplicate.toMap();const auto file=row.value("path").toString();
                if(!unchanged(keep,hash,cancel) || !unchanged(row,hash,cancel)) {errors.append(tr("文件已变化，跳过：%1").arg(file));continue;}
                if(recycle && !QFile::moveToTrash(file)){errors.append(tr("无法移入回收站，保留索引：%1").arg(file));continue;}
                if(!db.mergeDuplicate(row,keep,hash,!recycle)){errors.append(tr("索引合并失败：%1").arg(file));continue;}
                redirects.append(QVariantMap{{"from",row},{"to",keep}});
            }
        }
        return QVariantMap{{"redirects",redirects},{"errors",errors}};
    }));
}
}
