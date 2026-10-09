#include "sound_effects.h"
#include <algorithm>
#include <cmath>
#include <numbers>
// Verblib 0.5 from miniaudio 0.11.23, MIT-0. Original header is unmodified.
// Five times 44.1 kHz accommodates 192 kHz without resampling the music.
#define verblib_max_sample_rate_multiplier 5
#define VERBLIB_IMPLEMENTATION
#include "third_party/verblib/verblib.h"

namespace listenfree::media {
SoundEffectParameters SoundEffectParameters::fromMap(const QVariantMap& v) {
    SoundEffectParameters p;
    auto number = [&v](const char* key, double fallback, double lo, double hi) {
        bool ok = false; const double n = v.value(key, fallback).toDouble(&ok);
        return ok && std::isfinite(n) ? std::clamp(n, lo, hi) : fallback;
    };
    p.reverbEnabled=v.value("reverbEnabled",false).toBool();
    p.surroundEnabled=v.value("surroundEnabled",false).toBool();
    p.mono=v.value("mono",false).toBool();
    p.room=number("room",.5,.1,.92); p.damping=number("damping",.5,0,1);
    p.wet=number("wet",.18,0,.6); p.depth=number("depth",.65,0,1);
    p.period=number("period",12,4,40); p.width=number("width",1,0,2);
    p.balance=number("balance",0,-1,1);
    return p;
}
QVariantMap SoundEffectParameters::toMap() const {
    return {{"reverbEnabled",reverbEnabled},{"surroundEnabled",surroundEnabled},{"mono",mono},
        {"room",room},{"damping",damping},{"wet",wet},{"depth",depth},{"period",period},
        {"width",width},{"balance",balance}};
}
struct SoundEffects::State {
    SoundEffectParameters p;
    unsigned rate{0}, channels{0};
    std::unique_ptr<verblib> verb;
    double phase{0}, wet{0}, width{1}, pan{0}, mono{0}, protection{1};
    double smoothing{.001}, release{.0002};
    bool initialized{false};
};
SoundEffects::SoundEffects() : d(std::make_unique<State>()) {}
SoundEffects::~SoundEffects() = default;
bool SoundEffects::reverbSupported() const {
    return d->channels>=1 && d->channels<=2 && d->rate>=22050 && d->rate<=220500;
}
void SoundEffects::configure(unsigned rate, unsigned channels) {
    d->rate=rate; d->channels=channels;
    d->phase=0; d->wet=0; d->width=1; d->pan=0; d->mono=0; d->protection=1;
    d->verb.reset(); d->initialized=false;
    if(rate) { d->smoothing=1-std::exp(-1.0/(rate*.015)); d->release=1-std::exp(-1.0/(rate*.1)); }
    setParameters(d->p);
}
void SoundEffects::setParameters(const SoundEffectParameters& p) {
    d->p=p;
    if(p.reverbEnabled && reverbSupported()) {
        if(!d->verb) {
            d->verb=std::make_unique<verblib>();
            verblib_initialize(d->verb.get(),d->rate,d->channels);
            verblib_set_dry(d->verb.get(),0);
            verblib_set_wet(d->verb.get(),1.0f/3); // normalized wet output, mixed below
            verblib_set_width(d->verb.get(),1);
        }
        verblib_set_room_size(d->verb.get(),float(p.room));
        verblib_set_damping(d->verb.get(),float(p.damping));
    }
    if(!d->initialized && d->rate) {
        d->wet=p.reverbEnabled && d->verb?p.wet:0;
        d->width=p.width; d->pan=p.balance; d->mono=p.mono?1:0;
        d->initialized=true;
    }
}
void SoundEffects::process(float* samples, unsigned frames) {
    if(!samples || !d->rate || d->channels<1) return;
    const auto& p=d->p;
    const double targetWet=p.reverbEnabled && d->verb?p.wet:0;
    auto follow=[this](double& value, double target) {
        value+=(target-value)*d->smoothing;
        if(std::abs(value-target)<1e-7)value=target;
    };
    const bool settled = d->wet==0 && d->width==1 && d->pan==0 && d->mono==0 && d->protection==1;
    if(!p.reverbEnabled && !p.surroundEnabled && !p.mono && p.width==1 && p.balance==0 && settled) {
        d->verb.reset(); // release delay storage after fading out; disabled steady state is a bypass
        return;
    }
    // More than two channels are preserved as supplied; never reinterpret a
    // surround layout as alternating stereo or downmix without a channel map.
    if(d->channels>2)return;
    for(unsigned frame=0;frame<frames;++frame) {
        float* s=samples+frame*d->channels;
        follow(d->wet,targetWet); follow(d->width,p.width); follow(d->mono,p.mono?1:0);
        const double rotation=p.surroundEnabled?std::sin(d->phase)*p.depth:0;
        follow(d->pan,std::clamp(p.balance+rotation,-1.0,1.0));
        if(p.surroundEnabled) {
            d->phase+=2*std::numbers::pi/(p.period*d->rate);
            if(d->phase>=2*std::numbers::pi)d->phase-=2*std::numbers::pi;
        }
        if(d->verb && d->wet>0) {
            float tail[2]{};
            verblib_process(d->verb.get(),s,tail,1);
            for(unsigned c=0;c<d->channels;++c)s[c]=float(s[c]*(1-.25*d->wet)+tail[c]*d->wet);
        }
        if(d->channels==2) {
            // Qmmp Extra Stereo's mid/side width; blend mono without allocating.
            const double mid=(s[0]+s[1])*.5;
            const double side=(s[0]-s[1])*.5*d->width*(1-d->mono);
            double l=mid+side, r=mid-side;
            // W3C equal-power stereo panning. Center is an exact bypass and
            // rotation is driven by PCM frames, so it stops with the music.
            if(d->pan<0) { const double angle=(d->pan+1)*std::numbers::pi*.5; l+=r*std::cos(angle); r*=std::sin(angle); }
            else if(d->pan>0) { const double angle=d->pan*std::numbers::pi*.5; r+=l*std::sin(angle); l*=std::cos(angle); }
            s[0]=float(l);s[1]=float(r);
        }
        // Linked sample-peak safety gain, only active on actual over-level
        // samples. No auto make-up, lookahead buffer or loudness pumping at unity.
        double peak=0;for(unsigned c=0;c<d->channels;++c)peak=std::max(peak,std::abs(double(s[c])));
        const double wanted=peak>1?1/peak:1;
        d->protection=wanted<d->protection?wanted:d->protection+(1-d->protection)*d->release;
        if(d->protection>1-1e-7)d->protection=1;
        for(unsigned c=0;c<d->channels;++c)s[c]=float(s[c]*d->protection);
    }
    if(!p.reverbEnabled && d->wet==0)d->verb.reset();
}
}
