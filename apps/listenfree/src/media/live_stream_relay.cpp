#include "live_stream_relay.h"
#include <QUuid>
#include <QLoggingCategory>
#include <QtConcurrentRun>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/packet.h>
}

namespace listenfree::media {
Q_LOGGING_CATEGORY(liveLog,"listenfree.radio.relay")
struct LiveStreamRelay::Job {
    std::atomic_bool cancelled{false};
    std::atomic<qint64> deadline{};
    std::mutex mutex;std::condition_variable available;
    QByteArray bytes,contentType;QString error;bool done{};
    static qint64 now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
    void arm(){deadline=now()+15000;}
    static int interrupt(void* opaque){const auto* job=static_cast<Job*>(opaque);return job->cancelled || now()>job->deadline.load();}
    static int write(void* opaque,const uint8_t* data,int size) {
        auto* job=static_cast<Job*>(opaque);std::unique_lock lock(job->mutex);
        job->available.wait(lock,[job,size]{return job->cancelled || job->bytes.size()+size<=512*1024;});
        if(job->cancelled)return AVERROR_EXIT;
        job->bytes.append(reinterpret_cast<const char*>(data),size);return size;
    }
};
LiveStreamRelay::LiveStreamRelay(QObject* parent):QObject(parent) {
    pump_.setInterval(20);connect(&pump_,&QTimer::timeout,this,&LiveStreamRelay::drain);
    connect(&worker_,&QFutureWatcherBase::finished,this,[this]{if(!started_ && client_)start();});
    connect(&server_,&QTcpServer::newConnection,this,[this] {
        while(server_.hasPendingConnections()) {
            auto* socket=server_.nextPendingConnection();socket->setReadBufferSize(8192);
            connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
            QTimer::singleShot(10000,socket,[socket]{if(!socket->property("served").toBool())socket->abort();});
            connect(socket,&QTcpSocket::readyRead,this,[this,socket] {
                if(socket->property("served").toBool())return;
                const auto request=socket->property("request").toByteArray()+socket->readAll();
                if(request.size()>8192){socket->abort();return;}
                if(!request.contains("\r\n\r\n")){socket->setProperty("request",request);return;}
                socket->setProperty("served",true);
                const auto first=request.left(request.indexOf('\n')).trimmed().split(' ');
                qCDebug(liveLog)<<"decoder request"<<first.value(0)<<"matching path"<<(first.value(1)==path_)<<"occupied"<<bool(client_);
                if(path_.isEmpty() || first.size()!=3 || first[1]!=path_ || first[0]!="GET" || client_) {
                    socket->write("HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n");socket->disconnectFromHost();return;
                }
                client_=socket;
                connect(socket,&QTcpSocket::disconnected,this,[this,socket]{if(client_==socket)cancel();});
                start();pump_.start();
            });
        }
    });
}
LiveStreamRelay::~LiveStreamRelay(){cancel();worker_.waitForFinished();}
QUrl LiveStreamRelay::publish(const QUrl& url) {
    cancel();if((url.scheme()!="https" && url.scheme()!="http") || url.host().isEmpty())return {};
    if(!server_.isListening() && !server_.listen(QHostAddress::LocalHost,0))return {};
    upstream_=url;path_='/'+QUuid::createUuid().toByteArray(QUuid::WithoutBraces)+"/live";
    return QUrl(QStringLiteral("http://127.0.0.1:%1%2").arg(server_.serverPort()).arg(QString::fromLatin1(path_)));
}
void LiveStreamRelay::cancel() {
    path_.clear();upstream_.clear();started_=false;pump_.stop();
    if(job_){job_->cancelled=true;job_->available.notify_all();job_.reset();}
    if(client_){auto* socket=client_.data();client_=nullptr;socket->abort();}
}
void LiveStreamRelay::start() {
    if(started_ || worker_.isRunning() || !client_ || path_.isEmpty())return;
    started_=true;job_=std::make_shared<Job>();
    qCDebug(liveLog)<<"starting demux worker";
    worker_.setFuture(QtConcurrent::run(&LiveStreamRelay::remux,job_,upstream_));
}
void LiveStreamRelay::drain() {
    if(!job_ || !client_)return;
    QByteArray data,contentType;QString error;bool done=false;
    {
        std::lock_guard lock(job_->mutex);
        if(client_->bytesToWrite()<262144) {data=job_->bytes.left(65536);job_->bytes.remove(0,data.size());}
        done=job_->done && job_->bytes.isEmpty();error=job_->error;contentType=job_->contentType;
    }
    job_->available.notify_one();
    if(!client_->property("headersSent").toBool() && (!contentType.isEmpty() || done)) {
        client_->write("HTTP/1.0 200 OK\r\nContent-Type: "+(contentType.isEmpty()?QByteArray("application/octet-stream"):contentType)+"\r\nConnection: close\r\n\r\n");client_->setProperty("headersSent",true);
    }
    if(!data.isEmpty())client_->write(data);
    if(done) {pump_.stop();if(!error.isEmpty())emit errorOccurred(error);if(client_)client_->disconnectFromHost();}
}
void LiveStreamRelay::remux(const std::shared_ptr<Job>& job,const QUrl& url) {
    AVFormatContext* input=avformat_alloc_context();AVFormatContext* output=nullptr;
    AVIOContext* io=nullptr;AVPacket* packet=av_packet_alloc();AVDictionary* options=nullptr;
    int result=AVERROR(ENOMEM);int audio=-1;bool header=false;
    const auto address=url.toEncoded();
    if(input && packet) {
        job->arm();input->interrupt_callback={&Job::interrupt,job.get()};
        av_dict_set(&options,"rw_timeout","15000000",0);
        av_dict_set(&options,"user_agent","ListenFree/0.3",0);
        av_dict_set(&options,"protocol_whitelist","http,https,tcp,tls,crypto",0);
        av_dict_set(&options,"analyzeduration","1000000",0);av_dict_set(&options,"probesize","262144",0);
        result=avformat_open_input(&input,address.constData(),nullptr,&options);av_dict_free(&options);
        qCDebug(liveLog)<<"opened HLS input"<<result;
        if(result>=0){job->arm();result=avformat_find_stream_info(input,nullptr);}
        if(result>=0){audio=av_find_best_stream(input,AVMEDIA_TYPE_AUDIO,-1,-1,nullptr,0);result=audio<0?audio:0;}
        if(result>=0) {
            const auto codec=input->streams[audio]->codecpar->codec_id;
            const bool aac=codec==AV_CODEC_ID_AAC,mp3=codec==AV_CODEC_ID_MP3 || codec==AV_CODEC_ID_MP2;
            result=avformat_alloc_output_context2(&output,nullptr,aac?"adts":mp3?"mp3":"matroska",nullptr);
            std::lock_guard lock(job->mutex);job->contentType=aac?"audio/aac":mp3?"audio/mpeg":"audio/x-matroska";
        }
        if(result>=0 && output) {
            auto* stream=avformat_new_stream(output,nullptr);
            result=stream?avcodec_parameters_copy(stream->codecpar,input->streams[audio]->codecpar):AVERROR(ENOMEM);
            if(result>=0){stream->codecpar->codec_tag=0;stream->time_base=input->streams[audio]->time_base;}
        }
        if(result>=0) {
            auto* buffer=static_cast<uint8_t*>(av_malloc(32768));
            io=buffer?avio_alloc_context(buffer,32768,1,job.get(),nullptr,&Job::write,nullptr):nullptr;
            if(!io){av_free(buffer);result=AVERROR(ENOMEM);}
            else {
                io->seekable=0;output->pb=io;output->flags|=AVFMT_FLAG_CUSTOM_IO|AVFMT_FLAG_FLUSH_PACKETS;
                av_dict_set(&options,"live","1",0);av_dict_set(&options,"cluster_time_limit","250",0);
                result=avformat_write_header(output,&options);av_dict_free(&options);header=result>=0;
                qCDebug(liveLog)<<"stream header"<<result;
            }
        }
        while(result>=0 && !job->cancelled) {
            job->arm();result=av_read_frame(input,packet);if(result<0)break;
            if(packet->stream_index!=audio){av_packet_unref(packet);continue;}
            av_packet_rescale_ts(packet,input->streams[audio]->time_base,output->streams[0]->time_base);
            packet->stream_index=0;packet->pos=-1;result=av_interleaved_write_frame(output,packet);
            avio_flush(io);
        }
        if(header && !job->cancelled)av_write_trailer(output);
    }
    av_packet_free(&packet);avformat_close_input(&input);
    if(io){av_freep(&io->buffer);avio_context_free(&io);}avformat_free_context(output);
    std::lock_guard lock(job->mutex);job->done=true;
    if(!job->cancelled && result<0 && result!=AVERROR_EOF) {
        char message[AV_ERROR_MAX_STRING_SIZE]{};av_strerror(result,message,sizeof(message));
        job->error=QStringLiteral("直播暂时中断：%1").arg(QString::fromUtf8(message));
        qWarning().noquote()<<job->error;
    }
}
}
