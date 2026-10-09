#include "audio_tail_probe.h"
#include <QtConcurrentRun>
#include <atomic>
#include <utility>
#include <chrono>
#include <cmath>
#include <algorithm>
#include <limits>
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/samplefmt.h>
}
namespace listenfree::media {
struct AudioTailProbe::Job {
    std::atomic_bool cancelled{false};
    std::chrono::steady_clock::time_point deadline;
    static int interrupt(void* opaque) {
        const auto* job=static_cast<Job*>(opaque);
        return job->cancelled || std::chrono::steady_clock::now()>job->deadline;
    }
};
AudioTailProbe::AudioTailProbe(QObject* parent):QObject(parent) {
    connect(&worker_,&QFutureWatcherBase::finished,this,[this]{
        const bool current=job_ && !job_->cancelled;
        const auto result=worker_.result();job_.reset();
        if(current)emit finished(result);
        startPending();
    });
}
AudioTailProbe::~AudioTailProbe(){cancel();}
void AudioTailProbe::cancel(){if(job_)job_->cancelled=true;pendingSource_.clear();}
void AudioTailProbe::request(const QString& source,qint64 durationMs){
    cancel();pendingSource_=source;pendingDuration_=durationMs;
    if(!worker_.isRunning() && !job_)startPending();
}
void AudioTailProbe::startPending(){
    if(pendingSource_.isEmpty() || job_)return;
    const auto source=std::exchange(pendingSource_,QString{});
    job_=std::make_shared<Job>();
    worker_.setFuture(QtConcurrent::run(&AudioTailProbe::analyze,job_,source,pendingDuration_));
}
namespace {
// Inspect channels separately: an antiphase stereo mix must not cancel to silence.
// This follows Mixxx's last-sound scan, with a more conservative -80 dB threshold.
template<class T> int lastSound(const AVFrame* frame,double scale,double bias=0) {
    const int channels=frame->ch_layout.nb_channels;
    const bool planar=av_sample_fmt_is_planar(AVSampleFormat(frame->format));
    for(int i=frame->nb_samples-1;i>=0;--i)for(int ch=0;ch<channels;++ch){
        const auto* data=reinterpret_cast<const T*>(frame->extended_data[planar?ch:0]);
        const double value=(double(data[planar?i:i*channels+ch])-bias)*scale;
        if(!std::isfinite(value))return -2;
        if(std::abs(value)>=0.0001)return i;
    }
    return -1;
}
int lastSound(const AVFrame* frame){
    switch(av_get_packed_sample_fmt(AVSampleFormat(frame->format))){
    case AV_SAMPLE_FMT_U8:return lastSound<uint8_t>(frame,1.0/128,128);
    case AV_SAMPLE_FMT_S16:return lastSound<int16_t>(frame,1.0/32768);
    case AV_SAMPLE_FMT_S32:return lastSound<int32_t>(frame,1.0/2147483648.0);
    case AV_SAMPLE_FMT_S64:return lastSound<int64_t>(frame,1.0/9223372036854775808.0);
    case AV_SAMPLE_FMT_FLT:return lastSound<float>(frame,1);
    case AV_SAMPLE_FMT_DBL:return lastSound<double>(frame,1);
    default:return -2;
    }
}
struct DecoderScope {
    AVFormatContext* input=avformat_alloc_context();
    AVCodecContext* decoder=nullptr;
    AVPacket* packet=av_packet_alloc();
    AVFrame* frame=av_frame_alloc();
    ~DecoderScope(){av_frame_free(&frame);av_packet_free(&packet);avcodec_free_context(&decoder);avformat_close_input(&input);}
};
}
qint64 AudioTailProbe::analyze(const std::shared_ptr<Job>& job,const QString& source,qint64 durationMs){
    job->deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(3500);
    if(job->cancelled)return -1;
    DecoderScope d;
    if(!d.input || !d.packet || !d.frame)return -1;
    d.input->interrupt_callback={&Job::interrupt,job.get()};
    AVDictionary* options=nullptr;
    av_dict_set(&options,"probesize","262144",0);
    av_dict_set(&options,"analyzeduration","1000000",0);
    av_dict_set(&options,"rw_timeout","1500000",0);
    const int opened=avformat_open_input(&d.input,source.toUtf8().constData(),nullptr,&options);
    av_dict_free(&options);
    if(opened<0 || Job::interrupt(job.get()) || avformat_find_stream_info(d.input,nullptr)<0)return -1;
    const AVCodec* codec=nullptr;
    const int index=av_find_best_stream(d.input,AVMEDIA_TYPE_AUDIO,-1,-1,&codec,0);
    if(index<0 || !codec || !d.input->pb || !(d.input->pb->seekable&AVIO_SEEKABLE_NORMAL))return -1;
    const auto* stream=d.input->streams[index];
    const auto timeBase=stream->time_base;
    const qint64 origin=stream->start_time==AV_NOPTS_VALUE?0:stream->start_time;
    const auto actualDuration=stream->duration!=AV_NOPTS_VALUE?av_rescale_q(stream->duration,timeBase,AVRational{1,1000}):
        d.input->duration!=AV_NOPTS_VALUE?d.input->duration/1000:durationMs;
    if(actualDuration<=0 || std::abs(actualDuration-durationMs)>1000)return -1;
    d.decoder=avcodec_alloc_context3(codec);
    if(!d.decoder || avcodec_parameters_to_context(d.decoder,stream->codecpar)<0)return -1;
    d.decoder->thread_count=1;
    if(avcodec_open2(d.decoder,codec,nullptr)<0)return -1;
    const qint64 startMs=std::max<qint64>(0,actualDuration-30000);
    if(av_seek_frame(d.input,index,origin+av_rescale_q(startMs,AVRational{1,1000},timeBase),AVSEEK_FLAG_BACKWARD)<0)return -1;
    avcodec_flush_buffers(d.decoder);
    qint64 last=-1,end=-1,decodedFrames=0,bytes=0;
    bool valid=true;
    const auto receive=[&]{
        int result=0;
        while((result=avcodec_receive_frame(d.decoder,d.frame))>=0){
            const auto* f=d.frame;
            if(Job::interrupt(job.get()) || f->sample_rate<=0 || f->ch_layout.nb_channels<1 || f->ch_layout.nb_channels>32 || f->best_effort_timestamp==AV_NOPTS_VALUE){valid=false;break;}
            decodedFrames+=f->nb_samples;
            if(decodedFrames>qint64(f->sample_rate)*35000/1000){valid=false;break;}
            const qint64 begin=av_rescale_q(f->best_effort_timestamp-origin,timeBase,AVRational{1,1000});
            if(end>=0 && begin>end+100){valid=false;break;} // incomplete coverage is not an outro
            const int sound=lastSound(f);
            if(sound==-2){valid=false;break;}
            if(sound>=0)last=begin+qint64(sound+1)*1000/f->sample_rate;
            end=begin+qint64(f->nb_samples)*1000/f->sample_rate;
            av_frame_unref(d.frame);
        }
        if(result!=AVERROR(EAGAIN) && result!=AVERROR_EOF && result<0)valid=false;
    };
    int result=0;
    while(valid && !Job::interrupt(job.get()) && (result=av_read_frame(d.input,d.packet))>=0){
        bytes+=d.packet->size;
        if(bytes>32*1024*1024){valid=false;break;}
        if(d.packet->stream_index==index){
            const auto sent=avcodec_send_packet(d.decoder,d.packet);
            if(sent<0){valid=false;break;}
            receive();
        }
        av_packet_unref(d.packet);
    }
    if(!valid || Job::interrupt(job.get()) || result!=AVERROR_EOF)return -1;
    if(avcodec_send_packet(d.decoder,nullptr)<0)return -1;
    receive();
    if(!valid || last<startMs || end<actualDuration-250 || end-last<450)return -1;
    return std::min<qint64>(durationMs,last+120);
}
}
