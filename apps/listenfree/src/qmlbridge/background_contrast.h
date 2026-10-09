#pragma once
#include <QObject>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <cmath>

// Presentation-only sampling of the already rendered background; no image I/O.
class BackgroundContrast : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool dark READ dark NOTIFY changed)
public:
    using QObject::QObject;
    bool dark() const { return dark_; }
    Q_INVOKABLE void sample(QQuickItem* source) {
        const auto generation=++generation_;
        if(!source)return;
        auto result=source->grabToImage(QSize(24,24));
        if(!result)return;
        connect(result.data(),&QQuickItemGrabResult::ready,this,[this,result,generation] {
            if(generation!=generation_ || result->image().isNull())return;
            const auto image=result->image();double luminance=0;
            for(int y=0;y<image.height();++y)for(int x=0;x<image.width();++x) {
                const auto c=image.pixelColor(x,y);
                luminance+=.2126*std::pow(c.redF(),2.2)+.7152*std::pow(c.greenF(),2.2)+.0722*std::pow(c.blueF(),2.2);
            }
            const bool value=luminance/(image.width()*image.height())<.28;
            if(dark_!=value){dark_=value;emit changed();}
        },Qt::SingleShotConnection);
    }
signals:
    void changed();
private:
    bool dark_=false;
    unsigned generation_=0;
};
