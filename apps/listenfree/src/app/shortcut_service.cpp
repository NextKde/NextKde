#include "shortcut_service.h"
#include <QApplication>
#include <QKeyEvent>
#include <windows.h>

namespace listenfree {
namespace {
QString prefix(const QString& group) { return "shortcuts." + group + "."; }
QString actionName(const QString& key) {
    const auto action = key.section('.', -1);
    static const QMap<QString, QString> names{{"playPause", "播放/暂停"}, {"previous", "上一首"},
        {"next", "下一首"}, {"focusSearch", "聚焦搜索"}, {"back", "返回"}, {"volumeUp", "提高音量"}, {"volumeDown", "降低音量"}};
    return names.value(action, action);
}
}
QMap<QString, QString> ShortcutService::defaults() {
    return {{prefix("application")+"playPause", "Ctrl+F5"}, {prefix("application")+"previous", "Ctrl+Left"},
        {prefix("application")+"next", "Ctrl+Right"}, {prefix("application")+"focusSearch", "F1"}, {prefix("application")+"back", "Esc"},
        {prefix("global")+"playPause", "Ctrl+Alt+F5"}, {prefix("global")+"previous", "Ctrl+Alt+Left"},
        {prefix("global")+"next", "Ctrl+Alt+Right"}, {prefix("global")+"volumeUp", "Ctrl+Alt+Up"},
        {prefix("global")+"volumeDown", "Ctrl+Alt+Down"}};
}
QString ShortcutService::NativeKey::identity() const { return QString::number(modifiers)+":"+QString::number(key); }
ShortcutService::NativeKey ShortcutService::nativeKey(const QKeySequence& sequence) {
    NativeKey out;
    if (sequence.count() != 1) return out;
    const auto combination = sequence[0];
    const auto key = combination.key();
    const auto mods = combination.keyboardModifiers();
    if (mods & Qt::ControlModifier) out.modifiers |= MOD_CONTROL;
    if (mods & Qt::AltModifier) out.modifiers |= MOD_ALT;
    if (mods & Qt::ShiftModifier) out.modifiers |= MOD_SHIFT;
    if (mods & Qt::MetaModifier) out.modifiers |= MOD_WIN;
    if (key >= Qt::Key_A && key <= Qt::Key_Z) out.key = key;
    else if (key >= Qt::Key_0 && key <= Qt::Key_9) out.key = mods & Qt::KeypadModifier ? VK_NUMPAD0 + key-Qt::Key_0 : key;
    else if (key >= Qt::Key_F1 && key <= Qt::Key_F24) out.key = VK_F1 + key-Qt::Key_F1;
    else {
        static const QMap<int, unsigned int> keys{{Qt::Key_Left,VK_LEFT},{Qt::Key_Right,VK_RIGHT},
            {Qt::Key_Up,VK_UP},{Qt::Key_Down,VK_DOWN},{Qt::Key_Home,VK_HOME},{Qt::Key_End,VK_END},
            {Qt::Key_PageUp,VK_PRIOR},{Qt::Key_PageDown,VK_NEXT},{Qt::Key_Insert,VK_INSERT},{Qt::Key_Delete,VK_DELETE},
            {Qt::Key_Space,VK_SPACE},{Qt::Key_Tab,VK_TAB},{Qt::Key_Backtab,VK_TAB},{Qt::Key_Backspace,VK_BACK},
            {Qt::Key_Return,VK_RETURN},{Qt::Key_Enter,VK_RETURN},{Qt::Key_Escape,VK_ESCAPE},
            {Qt::Key_MediaPlay,VK_MEDIA_PLAY_PAUSE},{Qt::Key_MediaTogglePlayPause,VK_MEDIA_PLAY_PAUSE},
            {Qt::Key_MediaNext,VK_MEDIA_NEXT_TRACK},{Qt::Key_MediaPrevious,VK_MEDIA_PREV_TRACK},
            {Qt::Key_MediaStop,VK_MEDIA_STOP},{Qt::Key_VolumeUp,VK_VOLUME_UP},{Qt::Key_VolumeDown,VK_VOLUME_DOWN},
            {Qt::Key_VolumeMute,VK_VOLUME_MUTE}};
        out.key = keys.value(key);
        if (!out.key && key >= 0x20 && key < 0x7f) {
            const SHORT mapped = VkKeyScanExW(static_cast<WCHAR>(key), GetKeyboardLayout(0));
            if (mapped != -1) {
                out.key = LOBYTE(mapped);
                if (HIBYTE(mapped)&1) out.modifiers |= MOD_SHIFT;
                if (HIBYTE(mapped)&2) out.modifiers |= MOD_CONTROL;
                if (HIBYTE(mapped)&4) out.modifiers |= MOD_ALT;
            }
        }
    }
    return out;
}
QString ShortcutService::validate(const QString& text, bool global) {
    if (text.isEmpty()) return {};
    const auto sequence = QKeySequence::fromString(text, QKeySequence::PortableText);
    const auto native = nativeKey(sequence);
    if (sequence.count()!=1 || !native.key) return "无法识别该按键，请输入一个完整组合键，不能只使用修饰键。";
    const auto key = native.key, mods = native.modifiers;
    if ((mods&MOD_WIN) || ((mods&MOD_ALT) && (key==VK_TAB || key==VK_ESCAPE || key==VK_F4 || key==VK_SPACE))
        || ((mods&MOD_CONTROL) && key==VK_ESCAPE)
        || ((mods&(MOD_CONTROL|MOD_ALT))==(MOD_CONTROL|MOD_ALT) && key==VK_DELETE)
        || (global && key==VK_F12)) return "该组合键由 Windows 保留，请换一个按键。";
    const bool special = (key>=VK_F1 && key<=VK_F24) || (key>=VK_VOLUME_MUTE && key<=VK_MEDIA_PLAY_PAUSE);
    if (global && !special && !(mods&(MOD_CONTROL|MOD_ALT)))
        return "全局快捷键请搭配 Ctrl 或 Alt，避免影响其他应用的输入。";
    return {};
}
ShortcutService::ShortcutService(qmlbridge::SettingsController& settings, QObject* parent)
    : QObject(parent), settings_(settings), bindings_(defaults()) {
    setObjectName("shortcutService");
    // An unshown Qt-owned native window gives WM_HOTKEY the Qt event-filter
    // route and isolates IDs from other Qt/plugin registrations.
    receiverWindow_.setFlags(Qt::Tool | Qt::FramelessWindowHint);
    receiverWindow_.setObjectName("shortcutReceiver");
    receiver_ = reinterpret_cast<void*>(receiverWindow_.winId());
    qApp->installEventFilter(this);
    qApp->installNativeEventFilter(this);
    auto stored = bindings_;
    for (auto it=stored.begin(); it!=stored.end(); ++it) it.value()=settings_.value(it.key(),it.value()).toString();
    if (!commit(stored,settings_.value(prefix("application")+"enabled",true).toBool(),settings_.value(prefix("global")+"enabled",false).toBool())) {
        // A busy OS key on startup must not destroy the user's saved bindings.
        for (auto it=stored.cbegin(); it!=stored.cend(); ++it)
            if (validate(it.value(),it.key().startsWith(prefix("global"))).isEmpty()) bindings_[it.key()]=it.value();
        applicationEnabled_=settings_.value(prefix("application")+"enabled",true).toBool();
        globalEnabled_=false;
    }
    connect(&settings_, &qmlbridge::SettingsController::valueChanged, this, [this](const QString& key,const QVariant& value) {
        if (writing_ || settings_.applyingBatch() || !key.startsWith("shortcuts.")) return;
        const auto previous = bindings_.contains(key) ? QVariant(bindings_.value(key)) : QVariant(enabled(key.section('.',1,1)));
        bool ok=true;
        if (bindings_.contains(key)) ok=setBinding(key,value.toString());
        else if (key==prefix("global")+"enabled" || key==prefix("application")+"enabled") ok=setEnabled(key.section('.',1,1),value.toBool());
        if (!ok) { writing_=true; settings_.setValue(key,previous); writing_=false; }
    });
    connect(&settings_,&qmlbridge::SettingsController::valuesReloaded,this,[this](const QVariantMap& values) {
        bool changed=false;for(auto it=values.begin();it!=values.end();++it)changed|=it.key().startsWith("shortcuts.");
        if(!changed || writing_)return;
        auto desired=bindings_;
        for(auto it=desired.begin();it!=desired.end();++it)it.value()=settings_.value(it.key(),it.value()).toString();
        if(!commit(desired,settings_.value(prefix("application")+"enabled",true).toBool(),settings_.value(prefix("global")+"enabled",false).toBool()))settings_.rejectBatch();
    });
}
ShortcutService::~ShortcutService() {
    qApp->removeEventFilter(this); qApp->removeNativeEventFilter(this);
    for (const auto& binding : registered_) UnregisterHotKey(static_cast<HWND>(receiver_),binding.id);
    for (const auto& shortcut : local_) delete shortcut.data();
}
void ShortcutService::setWindow(QWindow* window) { window_=window; rebuildLocal(); }
bool ShortcutService::enabled(const QString& group) const { return group=="application" ? applicationEnabled_ : globalEnabled_; }
bool ShortcutService::fail(const QString& message,const QString& conflict) { error_=message; conflict_=conflict; ++revision_; emit changed(); return false; }
bool ShortcutService::commit(const QMap<QString, QString>& desired,bool application,bool global) {
    QMap<QString, Registration> next;
    QMap<QString, QString> conflicts;
    for (auto it=desired.cbegin();it!=desired.cend();++it) {
        const bool isGlobal=it.key().startsWith(prefix("global"));
        if (const auto error=validate(it.value(),isGlobal);!error.isEmpty()) return fail(error,it.key());
        if (it.value().isEmpty()) continue;
        const auto native=nativeKey(QKeySequence::fromString(it.value(),QKeySequence::PortableText));
        const auto identity=native.identity();
        const auto scoped=it.key().section('.',1,1)+identity;
        if (conflicts.contains(scoped)) return fail("与“"+actionName(conflicts.value(scoped))+"”的快捷键冲突，未保存。",conflicts.value(scoped));
        conflicts[scoped]=it.key();
        if (global && isGlobal) next[identity]={0,it.key().section('.',-1),it.value()};
    }
    QList<int> acquired;
    for (auto it=next.begin();it!=next.end();++it) {
        if (registered_.contains(it.key())) { it->id=registered_.value(it.key()).id; continue; }
        const auto native=nativeKey(QKeySequence::fromString(it->sequence,QKeySequence::PortableText));
        // Wrap within the application hotkey ID range, avoiding live registrations.
        do { if (++nextId_>0xbfff) nextId_=1; } while ([&]{for(const auto& r:registered_)if(r.id==nextId_)return true;return acquired.contains(nextId_);}());
        if (!receiver_ || !RegisterHotKey(static_cast<HWND>(receiver_),nextId_,native.modifiers|MOD_NOREPEAT,native.key)) {
            for (const auto id:acquired) UnregisterHotKey(static_cast<HWND>(receiver_),id);
            return fail("“"+actionName(prefix("global")+it->action)+"”的 "+it->sequence+" 被系统或其他程序占用，未更改原绑定。",prefix("global")+it->action);
        }
        it->id=nextId_; acquired.append(nextId_);
    }
    QVariantMap updates, previous;
    for(auto it=desired.cbegin();it!=desired.cend();++it) updates[it.key()]=it.value();
    updates[prefix("application")+"enabled"]=application;
    updates[prefix("global")+"enabled"]=global;
    writing_=true;
    bool saved=true;
    for(auto it=updates.cbegin();it!=updates.cend();++it) {
        previous[it.key()]=settings_.value(it.key(),it.value());
        settings_.setValue(it.key(),it.value());
        if(settings_.value(it.key(),it.value())!=it.value()) { saved=false; break; }
    }
    if(!saved) for(auto it=previous.cbegin();it!=previous.cend();++it) settings_.setValue(it.key(),it.value());
    writing_=false;
    if(!saved) { for(const auto id:acquired)UnregisterHotKey(static_cast<HWND>(receiver_),id);return fail("快捷键保存失败，原绑定仍然有效。"); }
    for(auto it=registered_.cbegin();it!=registered_.cend();++it) if(!next.contains(it.key()))UnregisterHotKey(static_cast<HWND>(receiver_),it->id);
    registered_=next; bindings_=desired; applicationEnabled_=application; globalEnabled_=global;
    error_.clear(); conflict_.clear(); ++revision_; rebuildLocal(); emit changed(); return true;
}
bool ShortcutService::setBinding(const QString& key,const QString& sequence) {
    if(!bindings_.contains(key))return fail("未知快捷键动作。");
    if(const auto error=validate(sequence,key.startsWith(prefix("global")));!error.isEmpty())return fail(error);
    if (!sequence.isEmpty()) {
        const auto identity = nativeKey(QKeySequence::fromString(sequence, QKeySequence::PortableText)).identity();
        for (auto it=bindings_.cbegin(); it!=bindings_.cend(); ++it)
            if (it.key()!=key && it.key().section('.',1,1)==key.section('.',1,1) && !it.value().isEmpty()
                && nativeKey(QKeySequence::fromString(it.value(),QKeySequence::PortableText)).identity()==identity)
                return fail("与“"+actionName(it.key())+"”的快捷键冲突，未保存。",it.key());
    }
    auto desired=bindings_;
    desired[key]=QKeySequence::fromString(sequence,QKeySequence::PortableText).toString(QKeySequence::PortableText);
    return commit(desired,applicationEnabled_,globalEnabled_);
}
bool ShortcutService::setEnabled(const QString& group,bool value) {
    if(group!="application" && group!="global")return false;
    cancelCapture();return commit(bindings_,group=="application"?value:applicationEnabled_,group=="global"?value:globalEnabled_);
}
bool ShortcutService::resetGroup(const QString& group) {
    if(group!="application" && group!="global")return false;
    cancelCapture();auto desired=bindings_;const auto base=defaults();
    for(auto it=desired.begin();it!=desired.end();++it)if(it.key().startsWith(prefix(group)))it.value()=base.value(it.key());
    return commit(desired,applicationEnabled_,globalEnabled_);
}
void ShortcutService::beginCapture(const QString& key) {
    if(!bindings_.contains(key))return;
    recording_=key;error_.clear();conflict_.clear();emit changed();
}
void ShortcutService::cancelCapture() { if(recording_.isEmpty())return;recording_.clear();emit changed(); }
void ShortcutService::dispatch(const QString& action) { if(recording_.isEmpty())emit activated(action); }
void ShortcutService::rebuildLocal() {
    for (const auto& shortcut : local_) delete shortcut.data();
    local_.clear();if(!window_ || !applicationEnabled_)return;
    for(auto it=bindings_.cbegin();it!=bindings_.cend();++it) {
        if(!it.key().startsWith(prefix("application")) || it.value().isEmpty())continue;
        const auto sequence=QKeySequence::fromString(it.value(),QKeySequence::PortableText);
        if(registered_.contains(nativeKey(sequence).identity()))continue; // WM_HOTKEY dispatches this once.
        auto* shortcut=new QShortcut(sequence,window_);
        shortcut->setContext(Qt::ApplicationShortcut);shortcut->setAutoRepeat(false);
        connect(shortcut,&QShortcut::activated,this,[this,action=it.key().section('.',-1)]{dispatch(action);});
        local_.append(shortcut);
    }
}
bool ShortcutService::eventFilter(QObject*,QEvent* event) {
    if(recording_.isEmpty())return false;
    if(event->type()==QEvent::WindowDeactivate || event->type()==QEvent::ApplicationDeactivate || event->type()==QEvent::MouseButtonPress) { cancelCapture();return false; }
    if(event->type()==QEvent::ShortcutOverride) { event->accept();return true; }
    if(event->type()==QEvent::KeyRelease) { event->accept();return true; }
    if(event->type()!=QEvent::KeyPress)return false;
    auto* key=static_cast<QKeyEvent*>(event);event->accept();
    if(key->isAutoRepeat())return true;
    if(key->key()==Qt::Key_Escape && key->modifiers()==Qt::NoModifier) { cancelCapture();return true; }
    if(key->key()==Qt::Key_Control || key->key()==Qt::Key_Shift || key->key()==Qt::Key_Alt || key->key()==Qt::Key_Meta || key->key()==Qt::Key_AltGr)return true;
    const auto sequence=QKeySequence(key->keyCombination()).toString(QKeySequence::PortableText);
    if(setBinding(recording_,sequence))cancelCapture();
    return true;
}
bool ShortcutService::nativeEventFilter(const QByteArray&,void* message,qintptr* result) {
    auto* msg=static_cast<MSG*>(message);
    if(msg->message!=WM_HOTKEY || msg->hwnd!=static_cast<HWND>(receiver_))return false;
    if (result) *result=0;
    for(const auto& binding:registered_)if(binding.id==static_cast<int>(msg->wParam)) {
        const auto sequence=binding.sequence;auto action=binding.action;
        if(!recording_.isEmpty()) { if(setBinding(recording_,sequence))cancelCapture();return true; }
        if(window_ && window_->isActive() && applicationEnabled_) {
            const auto identity=nativeKey(QKeySequence::fromString(sequence,QKeySequence::PortableText)).identity();
            for(auto it=bindings_.cbegin();it!=bindings_.cend();++it)if(it.key().startsWith(prefix("application")) && !it.value().isEmpty()
                && nativeKey(QKeySequence::fromString(it.value(),QKeySequence::PortableText)).identity()==identity) { action=it.key().section('.',-1);break; }
        }
        dispatch(action);return true;
    }
    return true;
}
}
