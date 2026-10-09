#include "sound_effects.h"
#include <QMutex>
#include <qmmp/effect.h>
#include <qmmp/effectfactory.h>

using listenfree::media::SoundEffectParameters;
using listenfree::media::SoundEffects;

namespace {
struct SharedParameters { QMutex mutex; SoundEffectParameters value; quint64 revision{0}; };
class SoundEffect final : public Effect {
public:
    explicit SoundEffect(SharedParameters& shared) : shared_(shared) {}
    void configure(quint32 rate, ChannelMap map) override {
        Effect::configure(rate,map);
        { QMutexLocker lock(&shared_.mutex); parameters_=shared_.value; revision_=shared_.revision; }
        dsp_.setParameters(parameters_); dsp_.configure(rate,unsigned(map.count()));
    }
    void applyEffect(Buffer* b) override {
        bool changed=false;
        if(shared_.mutex.tryLock()) {
            if(revision_!=shared_.revision){parameters_=shared_.value;revision_=shared_.revision;changed=true;}
            shared_.mutex.unlock();
        }
        if(changed)dsp_.setParameters(parameters_);
        if(channels()>0)dsp_.process(b->data,b->samples/unsigned(channels()));
    }
private:
    SharedParameters& shared_;
    SoundEffectParameters parameters_;
    quint64 revision_{0};
    SoundEffects dsp_;
};
}
class ListenFreeSoundFactory final : public QObject, public EffectFactory {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qmmp.qmmp.EffectFactoryInterface.1.0")
    Q_INTERFACES(EffectFactory)
public:
    EffectProperties properties() const override {
        EffectProperties p; p.name="ListenFree Sound"; p.shortName="listenfree_sound";
        // Before crossfade: analyze/mix already-processed decks consistently.
        p.priority=EffectProperties::EFFECT_PRIORITY_DEFAULT;return p;
    }
    Effect* create() override { return new SoundEffect(parameters_); }
    QDialog* createSettings(QWidget*) override { return nullptr; }
    void showAbout(QWidget*) override {}
    QString translation() const override { return {}; }
    Q_INVOKABLE void setParameters(QVariantMap values) {
        const auto p=SoundEffectParameters::fromMap(values);
        QMutexLocker lock(&parameters_.mutex);parameters_.value=p;++parameters_.revision;
    }
private:
    SharedParameters parameters_;
};
#include "sound_effect_plugin.moc"
