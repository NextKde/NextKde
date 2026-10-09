#pragma once
#include <memory>
#include <QVariantMap>

namespace listenfree::media {
struct SoundEffectParameters {
    bool reverbEnabled{false}, surroundEnabled{false}, mono{false};
    double room{.5}, damping{.5}, wet{.18}, depth{.65}, period{12}, width{1}, balance{0};
    static SoundEffectParameters fromMap(const QVariantMap& values);
    QVariantMap toMap() const;
};

// Qmmp owns the processing thread. No QML, network or device APIs in this DSP.
class SoundEffects final {
public:
    SoundEffects();
    ~SoundEffects();
    void configure(unsigned sampleRate, unsigned channels);
    void setParameters(const SoundEffectParameters& parameters);
    void process(float* samples, unsigned frames);
    bool reverbSupported() const;
private:
    struct State;
    std::unique_ptr<State> d;
};
}
