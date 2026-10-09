#include "portable_session.h"
#include "equalizer_presets.h"
#include "media/sound_effects.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QUuid>
#include <algorithm>
#include <cmath>

namespace listenfree::qmlbridge {
namespace {
QString json(const QVariant& value) { return QString::fromUtf8(QJsonDocument::fromVariant(value).toJson(QJsonDocument::Compact)); }
QVariantList validGains(const QVariant& value) {
    const auto list=value.toList();if(list.size()!=10)return {};
    QVariantList result;
    for(const auto& v:list) {bool ok=false;const double n=v.toDouble(&ok);if(!ok || !std::isfinite(n))return {};result.append(std::clamp(n,-12.0,12.0));}
    return result;
}
}
void PortableSession::loadAudioEffects() {
    auto read=[this](const char* key,const char* fallback) {return QByteArray::fromStdString(database_.getSetting(key).value_or(fallback));};
    equalizerEnabled_=read("audio.eq.enabled","false")=="true";
    equalizerGains_=validGains(QJsonDocument::fromJson(read("audio.eq.gains","[]")).toVariant());
    if(equalizerGains_.isEmpty())for(int i=0;i<10;++i)equalizerGains_.append(0.0);
    bool ok=false;double preamp=read("audio.eq.preamp","0").toDouble(&ok);
    equalizerPreamp_=ok && std::isfinite(preamp)?std::clamp(preamp,-12.0,12.0):0;
    equalizerAutoHeadroom_=read("audio.eq.autoHeadroom","true")=="true";
    for(const auto& value:QJsonDocument::fromJson(read("audio.eq.userPresets","[]")).array()) {
        auto preset=value.toVariant().toMap();const auto gains=validGains(preset.value("gains"));
        const auto id=preset.value("value").toString(),name=preset.value("label").toString().trimmed();
        const double gain=preset.value("preamp").toDouble();
        if(!id.startsWith("user-") || id.size()>48 || name.isEmpty() || name.size()>40 || gains.isEmpty() || !std::isfinite(gain))continue;
        bool duplicate=false;for(const auto& old:userEqualizerPresets_)if(old.toMap().value("value")==id)duplicate=true;
        if(duplicate)continue;
        preset={{"value",id},{"label",name},{"description",tr("我的预设")},{"builtin",false},{"gains",gains},{"preamp",std::clamp(gain,-12.0,12.0)}};
        userEqualizerPresets_.append(preset);if(userEqualizerPresets_.size()>=64)break;
    }
    equalizerPreset_="custom";
    const QString saved=QString::fromUtf8(read("audio.eq.preset","flat"));
    for(const auto& v:equalizerPresets()) {
        const auto p=v.toMap();if(p.value("value")==saved && p.value("gains").toList()==equalizerGains_ && p.value("preamp").toDouble()==equalizerPreamp_)equalizerPreset_=saved;
    }
    audioEffects_=media::SoundEffectParameters::fromMap(QJsonDocument::fromJson(read("audio.effects","{}")).toVariant().toMap()).toMap();
    applyEqualizer();
    audioEffectsAvailable_=player_.setSoundEffects(audioEffects_);
}
QVariantList PortableSession::equalizerPresets() const {
    auto list=builtinEqualizerPresets();list.append(userEqualizerPresets_);return list;
}
double PortableSession::equalizerEffectivePreamp() const {
    double peak=0;for(const auto& g:equalizerGains_)peak=std::max(peak,g.toDouble());
    return equalizerPreamp_-(equalizerAutoHeadroom_?peak:0);
}
void PortableSession::persistEqualizer() {
    database_.setSetting("audio.eq.enabled",equalizerEnabled_?"true":"false");
    database_.setSetting("audio.eq.gains",json(equalizerGains_));
    database_.setSetting("audio.eq.preamp",QString::number(equalizerPreamp_));
    database_.setSetting("audio.eq.autoHeadroom",equalizerAutoHeadroom_?"true":"false");
    database_.setSetting("audio.eq.preset",equalizerPreset_);
    applyEqualizer();emit equalizerChanged();
}
void PortableSession::applyEqualizer() {
    std::vector<double> gains;for(const auto& g:equalizerGains_)gains.push_back(g.toDouble());
    player_.setEqualizer(equalizerEnabled_,gains,equalizerPreamp_,equalizerAutoHeadroom_);
}
void PortableSession::setEqualizerEnabled(bool enabled) {equalizerEnabled_=enabled;persistEqualizer();}
void PortableSession::setEqualizerBand(int band,double gain) {
    if(band<0 || band>=10 || !std::isfinite(gain))return;
    equalizerGains_[band]=std::clamp(gain,-12.0,12.0);equalizerPreset_="custom";persistEqualizer();
}
void PortableSession::setEqualizerPreamp(double gain) {
    if(!std::isfinite(gain))return;
    equalizerPreamp_=std::clamp(gain,-12.0,12.0);equalizerPreset_="custom";persistEqualizer();
}
void PortableSession::setEqualizerAutoHeadroom(bool enabled) {equalizerAutoHeadroom_=enabled;persistEqualizer();}
void PortableSession::resetEqualizer() {
    equalizerGains_.clear();for(int i=0;i<10;++i)equalizerGains_.append(0.0);
    equalizerPreamp_=0;equalizerAutoHeadroom_=true;equalizerPreset_="flat";persistEqualizer();
}
void PortableSession::selectEqualizerPreset(const QString& id) {
    for(const auto& value:equalizerPresets()) {
        const auto p=value.toMap();if(p.value("value")!=id)continue;
        equalizerGains_=p.value("gains").toList();equalizerPreamp_=p.value("preamp").toDouble();
        equalizerPreset_=id;equalizerEnabled_=true;audioEffectsMessage_.clear();persistEqualizer();return;
    }
}
bool PortableSession::saveEqualizerPreset(const QString& rawName,bool overwrite) {
    const QString name=rawName.trimmed();
    auto fail=[this](const QString& text){audioEffectsMessage_=text;emit equalizerChanged();return false;};
    if(name.isEmpty() || name.size()>40)return fail(tr("预设名称需要 1–40 个字符。"));
    qsizetype target=-1;
    for(qsizetype i=0;i<userEqualizerPresets_.size();++i)
        if(userEqualizerPresets_[i].toMap().value("label").toString().compare(name,Qt::CaseInsensitive)==0)target=i;
    if(overwrite && target<0)return fail(tr("没有同名的个人预设，请另存为新预设。"));
    const QString targetId=target>=0?userEqualizerPresets_[target].toMap().value("value").toString():QString{};
    for(const auto& v:equalizerPresets()) {
        const auto p=v.toMap();if(p.value("label").toString().compare(name,Qt::CaseInsensitive)==0 && (!overwrite || p.value("value")!=targetId))
            return fail(tr("已有同名预设，请换个名称。"));
    }
    if(!overwrite && userEqualizerPresets_.size()>=64)return fail(tr("最多保存 64 个预设。"));
    const QString id=overwrite?targetId:"user-"+QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QVariantMap preset{{"value",id},{"label",name},{"description",tr("我的预设")},{"builtin",false},{"gains",equalizerGains_},{"preamp",equalizerPreamp_}};
    if(overwrite)userEqualizerPresets_[target]=preset;else userEqualizerPresets_.append(preset);
    database_.setSetting("audio.eq.userPresets",json(userEqualizerPresets_));equalizerPreset_=id;
    audioEffectsMessage_=tr("预设已保存");persistEqualizer();return true;
}
void PortableSession::deleteEqualizerPreset(const QString& id) {
    for(qsizetype i=0;i<userEqualizerPresets_.size();++i)if(userEqualizerPresets_[i].toMap().value("value")==id) {
        userEqualizerPresets_.removeAt(i);database_.setSetting("audio.eq.userPresets",json(userEqualizerPresets_));
        if(equalizerPreset_==id)equalizerPreset_="custom";
        audioEffectsMessage_=tr("预设已删除，当前曲线保留");persistEqualizer();return;
    }
}
void PortableSession::persistAudioEffects() {
    audioEffects_=media::SoundEffectParameters::fromMap(audioEffects_).toMap();
    database_.setSetting("audio.effects",json(audioEffects_));
    audioEffectsAvailable_=player_.setSoundEffects(audioEffects_);emit equalizerChanged();
}
void PortableSession::setAudioEffect(const QString& key,const QVariant& value) {
    if(!audioEffects_.contains(key))return;
    if(key!="reverbEnabled" && key!="surroundEnabled" && key!="mono") {
        bool ok=false;const double n=value.toDouble(&ok);if(!ok || !std::isfinite(n))return;
    }
    audioEffects_[key]=value;persistAudioEffects();
}
void PortableSession::setReverbPreset(const QString& id) {
    if(id=="room") {audioEffects_["room"]=.35;audioEffects_["damping"]=.65;audioEffects_["wet"]=.14;}
    else if(id=="hall") {audioEffects_["room"]=.7;audioEffects_["damping"]=.45;audioEffects_["wet"]=.24;}
    else if(id=="church") {audioEffects_["room"]=.88;audioEffects_["damping"]=.3;audioEffects_["wet"]=.32;}
    else return;
    audioEffects_["reverbEnabled"]=true;persistAudioEffects();
}
void PortableSession::resetAudioEffects() {audioEffects_=media::SoundEffectParameters{}.toMap();persistAudioEffects();}
}
