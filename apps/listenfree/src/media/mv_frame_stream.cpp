#include "mv_frame_stream.h"
#include <QAbstractVideoBuffer>
#include <QVideoFrameFormat>
#include <QPointer>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <limits>
#include <mutex>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
}

namespace listenfree::media {
namespace {
class AvFrameBuffer final : public QAbstractVideoBuffer {
public:
    explicit AvFrameBuffer(AVFrame* frame):frame_(frame) {}
    ~AvFrameBuffer() override { av_frame_free(&frame_); }
    MapData map(QVideoFrame::MapMode mode) override {
        MapData data;
        if(mode!=QVideoFrame::ReadOnly)return data;
        data.planeCount=3;
        for(int i=0;i<3;++i) {
            data.data[i]=frame_->data[i];data.bytesPerLine[i]=frame_->linesize[i];
            data.dataSize[i]=frame_->linesize[i]*(i?(frame_->height+1)/2:frame_->height);
        }
        return data;
    }
    QVideoFrameFormat format() const override {
        QVideoFrameFormat format(QSize(frame_->width,frame_->height),QVideoFrameFormat::Format_YUV420P);
        if(frame_->color_range==AVCOL_RANGE_JPEG)format.setColorRange(QVideoFrameFormat::ColorRange_Full);
        else if(frame_->color_range==AVCOL_RANGE_MPEG)format.setColorRange(QVideoFrameFormat::ColorRange_Video);
        switch(frame_->colorspace) {
        case AVCOL_SPC_BT709:format.setColorSpace(QVideoFrameFormat::ColorSpace_BT709);break;
        case AVCOL_SPC_BT470BG:case AVCOL_SPC_SMPTE170M:format.setColorSpace(QVideoFrameFormat::ColorSpace_BT601);break;
        default:format.setColorSpace(QVideoFrameFormat::ColorSpace_Undefined);break;
        }
        switch(frame_->color_trc) {
        case AVCOL_TRC_BT709:format.setColorTransfer(QVideoFrameFormat::ColorTransfer_BT709);break;
        case AVCOL_TRC_SMPTE170M:format.setColorTransfer(QVideoFrameFormat::ColorTransfer_BT601);break;
        case AVCOL_TRC_GAMMA22:format.setColorTransfer(QVideoFrameFormat::ColorTransfer_Gamma22);break;
        case AVCOL_TRC_GAMMA28:format.setColorTransfer(QVideoFrameFormat::ColorTransfer_Gamma28);break;
        default:break;
        }
        return format;
    }
private:
    AVFrame* frame_;
};
struct DecoderResources {
    AVFormatContext* format=nullptr;
    AVCodecContext* codec=nullptr;
    AVPacket* packet=av_packet_alloc();
    ~DecoderResources(){av_packet_free(&packet);avcodec_free_context(&codec);avformat_close_input(&format);}
};
}
struct MvFrameStream::Job {
    std::atomic_bool cancelled{false};
    std::atomic<qint64> deadline{0};
    std::mutex mutex;
    std::condition_variable wake;
    std::deque<QVideoFrame> frames;
    quint64 serial=0;
    qint64 seekMs=0,durationMs=0;
    bool fallback=false, eof=false;
    qint64 lastEndUs=0;
    static qint64 now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
    void arm(){deadline=now()+12000;}
    static int interrupt(void* opaque){const auto* job=static_cast<Job*>(opaque);return job->cancelled || now()>job->deadline.load();}
};
MvFrameStream::MvFrameStream(QObject* parent):QObject(parent) {
    pump_.setTimerType(Qt::PreciseTimer);pump_.setInterval(8);
    connect(&pump_,&QTimer::timeout,this,&MvFrameStream::drain);
}
MvFrameStream::~MvFrameStream(){stop();}
void MvFrameStream::stop() {
    pump_.stop();
    if(job_){job_->cancelled=true;job_->wake.notify_all();}
    if(worker_.joinable())worker_.join();
    job_.reset();ready_=false;endEmitted_=false;lateClock_.invalidate();
}
void MvFrameStream::open(const QUrl& url) {
    stop();job_=std::make_shared<Job>();anchorMs_=0;playing_=false;presented_=0;clock_.start();
    worker_=std::thread(&MvFrameStream::decode,job_,url);pump_.start();
}
qint64 MvFrameStream::position() const {return anchorMs_+(playing_&&clock_.isValid()?clock_.elapsed():0);}
qint64 MvFrameStream::duration() const {if(!job_)return 0;std::lock_guard lock(job_->mutex);return job_->durationMs;}
int MvFrameStream::queuedFrames() const {if(!job_)return 0;std::lock_guard lock(job_->mutex);return int(job_->frames.size());}
void MvFrameStream::synchronize(qint64 positionMs,bool playing,bool seek) {
    anchorMs_=qMax(qint64(0),positionMs);playing_=playing;clock_.restart();
    if(seek && job_) {
        lateClock_.invalidate();
        endEmitted_=false;
        {std::lock_guard lock(job_->mutex);job_->seekMs=anchorMs_;++job_->serial;job_->frames.clear();job_->eof=false;job_->lastEndUs=0;}
        job_->wake.notify_all();
    }
}
void MvFrameStream::drain() {
    if(!job_)return;
    QVideoFrame frame;bool fallback=false, ended=false;
    {
        std::lock_guard lock(job_->mutex);fallback=job_->fallback;
        const qint64 target=position()*1000;
        // Like Qt's renderer, present the frame covering the audio clock. Never
        // grow an event queue of AVFrames if the GUI is paused or blocked.
        while(!job_->frames.empty() && job_->frames.front().startTime()<=target) {
            frame=std::move(job_->frames.front());job_->frames.pop_front();
        }
        ended=playing_ && job_->eof && job_->frames.empty() && target>=job_->lastEndUs;
    }
    job_->wake.notify_all();
    if(fallback){pump_.stop();emit fallbackRequested();return;}
    if(frame.isValid()) {
        // A slower CPU must keep access to Qt's hardware decoder. Allow startup,
        // seeks and brief scheduling stalls; fall back on sustained decode lag.
        if(ready_ && playing_ && frame.endTime()<position()*1000-200000) {
            if(!lateClock_.isValid())lateClock_.start();
            else if(lateClock_.elapsed()>2000){pump_.stop();emit fallbackRequested();return;}
        } else lateClock_.invalidate();
        QPointer<MvFrameStream> guard(this);
        ++presented_;emit frameReady(frame);
        if(!guard)return;
        if(!ready_){ready_=true;emit ready();}
        if(!guard)return;
    }
    if(ended && !endEmitted_){endEmitted_=true;emit finished();}
}
void MvFrameStream::decode(const std::shared_ptr<Job>& job,const QUrl& url) {
    const auto fallback=[&]{std::lock_guard lock(job->mutex);if(!job->cancelled)job->fallback=true;};
    DecoderResources resource;
    resource.format=avformat_alloc_context();
    if(!resource.format || !resource.packet){fallback();return;}
    resource.format->interrupt_callback={&Job::interrupt,job.get()};job->arm();
    const auto encoded=url.isLocalFile()?url.toLocalFile().toUtf8():url.toEncoded();
    if(avformat_open_input(&resource.format,encoded.constData(),nullptr,nullptr)<0 ||
       avformat_find_stream_info(resource.format,nullptr)<0){fallback();return;}
    const int index=av_find_best_stream(resource.format,AVMEDIA_TYPE_VIDEO,-1,-1,nullptr,0);
    if(index<0){fallback();return;}
    auto* stream=resource.format->streams[index];const auto* parameters=stream->codecpar;
    const auto rate=av_guess_frame_rate(resource.format,stream,nullptr);
    // Narrow eligibility keeps HDR, unusual aspect ratios, rotation, >1080p and
    // other codecs on Qt's full-featured hardware backend.
    const auto aspect=av_guess_sample_aspect_ratio(resource.format,stream,nullptr);
    if(parameters->codec_id!=AV_CODEC_ID_H264 || parameters->width<=0 || parameters->height<=0 ||
       qMax(parameters->width,parameters->height)>1920 || qMin(parameters->width,parameters->height)>1080 ||
       (rate.den>0 && rate.num>60LL*rate.den) ||
       (aspect.num>0 && aspect.den>0 && aspect.num!=aspect.den) ||
       av_packet_side_data_get(parameters->coded_side_data,parameters->nb_coded_side_data,AV_PKT_DATA_DISPLAYMATRIX) ||
       parameters->color_trc==AVCOL_TRC_SMPTE2084 || parameters->color_trc==AVCOL_TRC_ARIB_STD_B67 ||
       parameters->color_space==AVCOL_SPC_BT2020_NCL || parameters->color_space==AVCOL_SPC_BT2020_CL) {
        fallback();return;
    }
    const auto* decoder=avcodec_find_decoder(parameters->codec_id);
    resource.codec=avcodec_alloc_context3(decoder);
    if(!resource.codec || avcodec_parameters_to_context(resource.codec,parameters)<0){fallback();return;}
    resource.codec->thread_count=rate.num>0 && rate.den>0 && rate.num<=31LL*rate.den?1:2;
    if(avcodec_open2(resource.codec,decoder,nullptr)<0){fallback();return;}
    for(unsigned i=0;i<resource.format->nb_streams;++i)if(int(i)!=index)resource.format->streams[i]->discard=AVDISCARD_ALL;
    const qint64 start=stream->start_time==AV_NOPTS_VALUE?0:stream->start_time;
    const qint64 nominalUs=rate.num>0?av_rescale_q(1,av_inv_q(rate),AV_TIME_BASE_Q):33333;
    {
        std::lock_guard lock(job->mutex);
        job->durationMs=stream->duration!=AV_NOPTS_VALUE?av_rescale_q(stream->duration,stream->time_base,{1,1000}):
            resource.format->duration!=AV_NOPTS_VALUE?resource.format->duration/1000:0;
    }
    quint64 serial=std::numeric_limits<quint64>::max();qint64 seekUs=0;bool eof=false;
    while(!job->cancelled) {
        quint64 currentSerial;qint64 seekMs;
        {
            std::unique_lock lock(job->mutex);
            job->wake.wait(lock,[&]{return job->cancelled || job->serial!=serial || (!eof && job->frames.size()<3);});
            if(job->cancelled)break;
            currentSerial=job->serial;seekMs=job->seekMs;
        }
        if(currentSerial!=serial) {
            const bool first=serial==std::numeric_limits<quint64>::max();
            serial=currentSerial;seekUs=seekMs*1000;
            if(!first || seekMs>0) {
                job->arm();const auto target=start+av_rescale_q(seekMs,{1,1000},stream->time_base);
                if(avformat_seek_file(resource.format,index,std::numeric_limits<qint64>::min(),target,target,AVSEEK_FLAG_BACKWARD)<0){fallback();return;}
            }
            avcodec_flush_buffers(resource.codec);eof=false;
        }
        auto* decoded=av_frame_alloc();
        if(!decoded){fallback();return;}
        int result=avcodec_receive_frame(resource.codec,decoded);
        if(result==0) {
            if((decoded->format!=AV_PIX_FMT_YUV420P && decoded->format!=AV_PIX_FMT_YUVJ420P) ||
               qMax(decoded->width,decoded->height)>1920 || qMin(decoded->width,decoded->height)>1080 ||
               decoded->linesize[0]<=0 || decoded->linesize[1]<=0 || decoded->linesize[2]<=0 ||
               (decoded->sample_aspect_ratio.num>0 && decoded->sample_aspect_ratio.den>0 && decoded->sample_aspect_ratio.num!=decoded->sample_aspect_ratio.den) ||
               (decoded->colorspace!=AVCOL_SPC_UNSPECIFIED && decoded->colorspace!=AVCOL_SPC_BT709 &&
                decoded->colorspace!=AVCOL_SPC_BT470BG && decoded->colorspace!=AVCOL_SPC_SMPTE170M) ||
               (decoded->color_trc!=AVCOL_TRC_UNSPECIFIED && decoded->color_trc!=AVCOL_TRC_BT709 &&
                decoded->color_trc!=AVCOL_TRC_SMPTE170M && decoded->color_trc!=AVCOL_TRC_GAMMA22 && decoded->color_trc!=AVCOL_TRC_GAMMA28) ||
               decoded->best_effort_timestamp==AV_NOPTS_VALUE ||
               av_frame_get_side_data(decoded,AV_FRAME_DATA_DISPLAYMATRIX) ||
               av_frame_get_side_data(decoded,AV_FRAME_DATA_MASTERING_DISPLAY_METADATA)) {
                av_frame_free(&decoded);fallback();return;
            }
            const qint64 pts=av_rescale_q(decoded->best_effort_timestamp-start,stream->time_base,AV_TIME_BASE_Q);
            const qint64 duration=decoded->duration>0?av_rescale_q(decoded->duration,stream->time_base,AV_TIME_BASE_Q):nominalUs;
            if(pts+duration<=seekUs){av_frame_free(&decoded);continue;}
            QVideoFrame frame(std::make_unique<AvFrameBuffer>(decoded));frame.setStartTime(pts);frame.setEndTime(pts+duration);
            std::lock_guard lock(job->mutex);
            if(job->serial==serial){job->lastEndUs=frame.endTime();job->frames.push_back(std::move(frame));}
            continue;
        }
        av_frame_free(&decoded);
        if(result==AVERROR_EOF){eof=true;std::lock_guard lock(job->mutex);if(job->serial==serial)job->eof=true;continue;}
        if(result!=AVERROR(EAGAIN)){fallback();return;}
        do {
            av_packet_unref(resource.packet);job->arm();result=av_read_frame(resource.format,resource.packet);
        }while(result>=0 && resource.packet->stream_index!=index && !job->cancelled);
        if(job->cancelled)break;
        if(result<0 && result!=AVERROR_EOF){fallback();return;}
        if(avcodec_send_packet(resource.codec,result==AVERROR_EOF?nullptr:resource.packet)<0){fallback();return;}
        av_packet_unref(resource.packet);
    }
}
}
