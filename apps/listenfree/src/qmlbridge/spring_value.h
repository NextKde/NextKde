#pragma once
#include <QAbstractAnimation>
#include <cmath>
#include <algorithm>

namespace listenfree::qmlbridge {
// Exact damped oscillator, preserving velocity on retarget.
// Parameters/solver follow AMLL utils/spring.ts (pushkine MIT attribution).
// Use Qt Quick's animation driver, shared with opacity/blur and display frames.
// No independent 16 ms timers, and no callbacks after convergence or hiding.
class SpringValue : public QAbstractAnimation {
    Q_OBJECT
    Q_PROPERTY(qreal target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(qreal value READ value NOTIFY valueChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(qreal stiffness MEMBER stiffness_)
    Q_PROPERTY(qreal damping MEMBER damping_)
    Q_PROPERTY(qreal mass MEMBER mass_)
public:
    explicit SpringValue(QObject* parent=nullptr):QAbstractAnimation(parent) {
        connect(this, &QAbstractAnimation::stateChanged, this, [this] { emit runningChanged(); });
    }
    int duration() const override { return -1; }
    qreal target() const { return target_; }
    qreal value() const { return value_; }
    bool enabled() const { return enabled_; }
    bool running() const { return state() == Running; }
    void setEnabled(bool enabled) {
        if (enabled_==enabled) return;
        enabled_=enabled;
        if (!enabled_) settle();
        emit enabledChanged();
    }
    void setTarget(qreal target) {
        if (!std::isfinite(target)) return;
        commitTarget(target);
    }
    Q_INVOKABLE void retarget(qreal target, qreal stiffness, qreal damping, qreal mass) {
        if (!std::isfinite(target) || !std::isfinite(stiffness) || !std::isfinite(damping) || !std::isfinite(mass)) return;
        // The last displayed sample and its velocity belong to the old
        // coefficients. Retarget continuously; Qt advances the next frame.
        stiffness_=stiffness; damping_=damping; mass_=mass;
        commitTarget(target);
    }
signals:
    void targetChanged();
    void valueChanged();
    void enabledChanged();
    void runningChanged();
protected:
    void updateCurrentTime(int currentTime) override {
        const double dt = double(currentTime - lastTime_) / 1000.;
        lastTime_ = currentTime;
        if (dt > 0) advance(dt);
    }
private:
    void commitTarget(qreal target) {
        if (target_==target && initialized_) return;
        target_=target;
        if (!enabled_ || !initialized_) { initialized_=true; settle(); }
        else if (!running()) { lastTime_=0; start(); }
        emit targetChanged();
    }
    int lastTime_=0;
    qreal value_=0, target_=0, velocity_=0, stiffness_=90, damping_=15, mass_=.9;
    bool initialized_=false, enabled_=true;
    void settle() { stop(); value_=target_; velocity_=0; emit valueChanged(); }
    void advance(double dt) {
        const double m=std::max(.01,mass_), k=std::max(.01,stiffness_), a=std::max(0.,damping_)/(2*m);
        const double x=value_-target_, v=velocity_, w2=k/m, discriminant=w2-a*a;
        if (discriminant<=0) {
            // AMLL's soft/overdamped branch uses the critically damped solution.
            const double w=std::sqrt(w2), b=v+w*x, decay=std::exp(-w*dt);
            value_=target_+(x+b*dt)*decay; velocity_=(v-w*b*dt)*decay;
        } else {
            const double w=std::sqrt(discriminant), b=(v+a*x)/w;
            const double c=std::cos(w*dt), s=std::sin(w*dt), decay=std::exp(-a*dt);
            const double position=x*c+b*s;
            value_=target_+decay*position;
            velocity_=decay*(-a*position-x*w*s+b*w*c);
        }
        if (std::abs(value_-target_)<.02 && std::abs(velocity_)<.02) settle();
        else emit valueChanged();
    }
};
}
