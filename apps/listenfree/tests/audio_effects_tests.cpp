#include "media/sound_effects.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>
#include <qmmp/effect.h>
#include <cmath>
#include <vector>
using namespace listenfree::media;
namespace {
std::vector<float> tone(unsigned rate,unsigned frames) {
    std::vector<float> data(frames*2);
    for(unsigned i=0;i<frames;++i)data[i*2]=data[i*2+1]=float(.1*std::sin(2*3.141592653589793*440*i/rate));
    return data;
}
double energy(const std::vector<float>& data,unsigned start,unsigned end,unsigned channel) {
    double sum=0;for(unsigned i=start;i<end;++i)sum+=double(data[i*2+channel])*data[i*2+channel];return sum;
}
}
class AudioEffectsTests final : public QObject {
    Q_OBJECT
    QTemporaryDir settings_;
private slots:
    void initTestCase() {
        QCoreApplication::setOrganizationName("ListenFreeAudioEffectsTests");
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,settings_.path());
    }
    void bypassIsBitExact() {
        auto pcm=tone(48000,2048),original=pcm;SoundEffects dsp;dsp.configure(48000,2);dsp.process(pcm.data(),2048);QVERIFY(pcm==original);
        dsp.configure(48000,6);dsp.process(pcm.data(),512);QVERIFY(pcm==original);
    }
    void reverbTail_data() {
        QTest::addColumn<unsigned>("rate");for(unsigned rate:{22050,44100,48000,96000,192000})QTest::newRow(qPrintable(QString::number(rate)))<<rate;
    }
    void reverbTail() {
        QFETCH(unsigned,rate);SoundEffects dsp;SoundEffectParameters p;p.reverbEnabled=true;p.wet=.3;p.room=.7;dsp.setParameters(p);dsp.configure(rate,2);QVERIFY(dsp.reverbSupported());
        std::vector<float> pcm(rate*4,0);pcm[0]=pcm[1]=.5f;dsp.process(pcm.data(),rate*2);
        QVERIFY(energy(pcm,rate/10,rate,0)>1e-6); // actual tail in previously silent input
        QVERIFY(energy(pcm,rate/10,rate/2,0)>energy(pcm,rate*3/2,rate*2,0));
        for(float v:pcm)QVERIFY(std::isfinite(v) && std::abs(v)<=1);
        p.reverbEnabled=false;dsp.setParameters(p);auto fresh=tone(rate,rate);dsp.process(fresh.data(),rate);
        fresh=tone(rate,1024);auto original=fresh;dsp.process(fresh.data(),1024);QVERIFY(fresh==original);
    }
    void unsupportedRatePreservesAudio() {
        SoundEffects dsp;SoundEffectParameters p;p.reverbEnabled=true;dsp.setParameters(p);dsp.configure(8000,2);QVERIFY(!dsp.reverbSupported());
        auto pcm=tone(8000,8000),original=pcm;dsp.process(pcm.data(),8000);QVERIFY(pcm==original);
        dsp.configure(384000,2);QVERIFY(!dsp.reverbSupported());dsp.process(pcm.data(),8000);QVERIFY(pcm==original);
    }
    void rotationMovesBothWays() {
        constexpr unsigned rate=48000;SoundEffects dsp;SoundEffectParameters p;p.surroundEnabled=true;p.depth=1;p.period=4;dsp.setParameters(p);dsp.configure(rate,2);
        auto pcm=tone(rate,rate*4);dsp.process(pcm.data(),rate*4);
        QVERIFY(energy(pcm,rate*9/10,rate*11/10,1)>20*energy(pcm,rate*9/10,rate*11/10,0));
        QVERIFY(energy(pcm,rate*29/10,rate*31/10,0)>20*energy(pcm,rate*29/10,rate*31/10,1));
    }
    void monoAndWidth() {
        constexpr unsigned rate=48000;auto pcm=tone(rate,1024);for(unsigned i=0;i<1024;++i)pcm[2*i+1]=-pcm[2*i];
        SoundEffects dsp;SoundEffectParameters p;p.mono=true;dsp.setParameters(p);dsp.configure(rate,2);dsp.process(pcm.data(),1024);
        for(float sample:pcm)QCOMPARE(sample,0.f);
        p.mono=false;p.width=2;dsp.setParameters(p);dsp.configure(rate,2);
        pcm=tone(rate,1024);const auto original=pcm;dsp.process(pcm.data(),1024);QVERIFY(pcm==original); // centered content remains centered
    }
    void pluginReceivesLiveParameters() {
        auto* factory=Effect::findFactory("listenfree_sound");QVERIFY(factory);
        auto* object=dynamic_cast<QObject*>(factory);QVERIFY(object);
        QVERIFY(QMetaObject::invokeMethod(object,"setParameters",Qt::DirectConnection,Q_ARG(QVariantMap,QVariantMap{})));
        std::unique_ptr<Effect> effect(Effect::create(factory));effect->configure(48000,ChannelMap(2));
        Buffer buffer(9600);buffer.samples=9600;
        std::fill(buffer.data,buffer.data+buffer.samples,.1f);effect->applyEffect(&buffer);QCOMPARE(buffer.data[9000],.1f);
        const QVariantMap values{{"mono",true}};
        QVERIFY(QMetaObject::invokeMethod(object,"setParameters",Qt::DirectConnection,Q_ARG(QVariantMap,values)));
        for(unsigned i=0;i<buffer.samples;i+=2){buffer.data[i]=.1f;buffer.data[i+1]=-.1f;}
        effect->applyEffect(&buffer);QVERIFY(std::abs(buffer.data[9000])<.001f);
    }
    void boundedCpuWork() {
        constexpr unsigned rate=48000;SoundEffects dsp;SoundEffectParameters p;p.reverbEnabled=true;p.surroundEnabled=true;dsp.setParameters(p);dsp.configure(rate,2);
        auto original=tone(rate,rate);auto pcm=original;QElapsedTimer timer;timer.start();
        for(int i=0;i<30;++i){pcm=original;dsp.process(pcm.data(),rate);}
        const double ms=timer.nsecsElapsed()/1e6;
        qInfo("30 s stereo PCM / all spatial effects: %.2f ms CPU wall time, %.3f%% of real time",ms,ms/300);
        QVERIFY(ms<3000); // headless DSP budget, not an application-wide CPU claim
    }
};
QTEST_GUILESS_MAIN(AudioEffectsTests)
#include "audio_effects_tests.moc"
