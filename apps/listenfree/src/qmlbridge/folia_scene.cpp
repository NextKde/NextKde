#include "folia_scene.h"
#include "fume_layout.h"
#include "diorama_geometry.h"
#include <QTextLayout>
#include <QTextBoundaryFinder>
#include <QFontMetricsF>
#include <QSGGeometryNode>
#include <QSGVertexColorMaterial>
#include <QQuaternion>
#include <QRegularExpression>
#include <QQuickItemGrabResult>
#include <array>
#include <algorithm>
#include <cmath>

namespace {
constexpr qreal pi=3.14159265358979323846;
qreal sat(qreal x){return std::clamp(x,0.,1.);}
qreal smoothStep(qreal x){x=sat(x);return x*x*(3-2*x);}
qreal out(qreal x){return 1-std::pow(1-sat(x),3);}
qreal mix(qreal a,qreal b,qreal t){return a+(b-a)*t;}
qreal randomUnit(const QString& seed,int n){return (FumeLayout::hash(seed+QString::number(n))%100000)/100000.;}
qreal envelope(qreal time,qreal start,qreal end){return smoothStep((time-start)/100.)*(1-smoothStep((time-end)/700.));}
QString lineText(const QVariantMap& m){return m.value("text",m.value("fullText",m.value("en"))).toString();}
QPointF rotated(qreal x,qreal y,qreal a){return {x*std::cos(a)-y*std::sin(a),x*std::sin(a)+y*std::cos(a)};}
qreal orbitRadius(qreal width,qreal energy){return std::min(width*.44,560.)*(1+energy*.08);}
QPointF orbitPoint(qreal radius,qreal psi){
    const qreal depth=(std::cos(psi)+1)/2;
    return rotated(std::sin(psi)*radius*(.35+.65*std::pow(depth,1.2)),std::cos(psi)*radius*.09,-pi/4);
}
QColor blendColor(const QColor& a,const QColor& b,qreal t,qreal alpha){
    return QColor::fromRgbF(mix(a.redF(),b.redF(),t),mix(a.greenF(),b.greenF(),t),mix(a.blueF(),b.blueF(),t),sat(alpha));
}
const QStringList shots={"pushIn","pullBack","orbit","track","crane","hold","swell","spiral","pendulum","flyby","float","glide","arc"};
const QStringList sonnetShots={"editorial-column","type-impact","fragment-collage","tracking-ribbon","mask-reveal","poster-blocks","quiet-tableau"};
}

void FoliaNodeModel::sync(const QVariantList& rows){
    // Keyed incremental updates preserve the QQuickText nodes through line changes.
    for(int i=0;i<rows.size();++i){
        const auto key=rows[i].toMap().value("key");
        if(i<rows_.size()&&rows_[i].toMap().value("key")==key){
            if(rows_[i]!=rows[i]){rows_[i]=rows[i];emit dataChanged(index(i),index(i));}
            continue;
        }
        int found=-1;for(int j=i+1;j<rows_.size();++j)if(rows_[j].toMap().value("key")==key){found=j;break;}
        if(found>=0){beginRemoveRows({},i,found-1);rows_.remove(i,found-i);endRemoveRows();if(rows_[i]!=rows[i]){rows_[i]=rows[i];emit dataChanged(index(i),index(i));}}
        else {beginInsertRows({},i,i);rows_.insert(i,rows[i]);endInsertRows();}
    }
    if(rows_.size()>rows.size()){beginRemoveRows({},rows.size(),rows_.size()-1);rows_.remove(rows.size(),rows_.size()-rows.size());endRemoveRows();}
}
FoliaScene::FoliaScene(QQuickItem* parent):QQuickItem(parent),model_(this){setClip(true);}
void FoliaScene::setLyrics(const QVariantList& v){if(v==lyrics_)return;lyrics_=v;compile();emit lyricsChanged();}
void FoliaScene::setStyle(const QString& v){if(v==style_)return;style_=v;model_.sync({});compile();emit styleChanged();}
void FoliaScene::setSeed(const QString& v){if(seed_==v)return;seed_=v;compile();emit lyricsChanged();}
void FoliaScene::setFontFamily(const QString& v){if(v==family_)return;family_=v;compile();emit lyricsChanged();}
void FoliaScene::setReducedMotion(bool v){if(v==reduced_)return;reduced_=v;updateDioramaCamera();emit frameChanged();}
void FoliaScene::setWordTiming(bool v){if(v==timed_)return;timed_=v;updateDioramaCamera();emit frameChanged();}
void FoliaScene::setEnergy(qreal v){if(qFuzzyCompare(energy_,v))return;energy_=sat(v);emit frameChanged();}
void FoliaScene::setAccentColor(const QColor& v){if(!v.isValid()||v==accent_)return;accent_=v;emit accentColorChanged();emit frameChanged();}
void FoliaScene::resetArtworkAccent(){++artworkGeneration_;setAccentColor(QColor("#ddd9d3"));}
QColor FoliaScene::accentFromImage(const QImage& input){
    // Small presentation sample, not another artwork decoder/cache. Saturated
    // hue families win over black borders and white typography on an album.
    if(input.isNull())return QColor("#ddd9d3");
    const QImage image=input.scaled(64,64,Qt::KeepAspectRatio,Qt::SmoothTransformation);
    struct Bucket {qreal weight=0,r=0,g=0,b=0;};std::array<Bucket,24> buckets{};
    for(int y=0;y<image.height();++y)for(int x=0;x<image.width();++x){
        const QColor c=image.pixelColor(x,y);const qreal saturation=c.hsvSaturationF(),value=c.valueF();
        if(c.alphaF()<.5||saturation<.16||value<.14)continue;
        const qreal weight=saturation*saturation*std::sqrt(value)*c.alphaF();
        auto& bucket=buckets[std::clamp(int(c.hsvHueF()*24),0,23)];
        bucket.weight+=weight;bucket.r+=c.redF()*weight;bucket.g+=c.greenF()*weight;bucket.b+=c.blueF()*weight;
    }
    int best=0;qreal bestWeight=0;
    for(int i=0;i<24;++i){const qreal weight=buckets[(i+23)%24].weight+buckets[i].weight+buckets[(i+1)%24].weight;if(weight>bestWeight){best=i;bestWeight=weight;}}
    if(bestWeight<std::max(1,image.width()*image.height())*.003)return QColor("#ddd9d3");
    Bucket sum;for(int offset=-1;offset<=1;++offset){const auto& b=buckets[(best+offset+24)%24];sum.weight+=b.weight;sum.r+=b.r;sum.g+=b.g;sum.b+=b.b;}
    const QColor color=QColor::fromRgbF(sum.r/sum.weight,sum.g/sum.weight,sum.b/sum.weight);
    return QColor::fromHsvF(color.hsvHueF(),std::clamp(qreal(color.hsvSaturationF()),.38,.72),std::clamp(qreal(color.valueF()),.88,.96));
}
void FoliaScene::sampleArtwork(QQuickItem* source){
    const unsigned generation=++artworkGeneration_;if(!source)return;
    auto result=source->grabToImage(QSize(64,64));if(!result)return;
    connect(result.data(),&QQuickItemGrabResult::ready,this,[this,result,generation]{
        if(generation==artworkGeneration_)setAccentColor(accentFromImage(result->image()));
    },Qt::SingleShotConnection);
}
void FoliaScene::geometryChange(const QRectF& n,const QRectF& o){QQuickItem::geometryChange(n,o);if(n.size()!=o.size())compile();}
void FoliaScene::setPosition(qreal v){
    if(!std::isfinite(v))return;position_=v;
    const int next=int(std::upper_bound(lines_.cbegin(),lines_.cend(),v,[](qreal t,const Line& l){return t<l.start;})-lines_.cbegin())-1;
    if(current_!=next){current_=next;rebuildWindow();emit currentChanged();}
    updateDioramaCamera();emit frameChanged();
}
QString FoliaScene::translation()const{return current_>=0&&current_<lines_.size()?lines_[current_].translation:QString{};}
QString FoliaScene::shotName()const{return current_<0?QString{}:style_=="diorama"?shots[lines_[current_].shot%13]:style_=="sonnet"?sonnetShots[lines_[current_].shot%7]:style_;}
QVariantList FoliaScene::layoutUnits()const{
    QVariantList result;if(current_<0||current_>=lines_.size())return result;const auto& l=lines_[current_];
    for(const auto& glyph:l.glyphs){if(glyph.text.trimmed().isEmpty())continue;
        if(result.isEmpty()||result.last().toMap().value("group").toInt()!=glyph.group)result.append(QVariantMap{{"group",glyph.group},{"displayText",glyph.text},{"originX",glyph.x},{"originY",glyph.y},{"measuredWidth",glyph.w},{"measuredHeight",l.font*1.2},{"fontSize",l.font}});
        else {auto unit=result.last().toMap();unit["displayText"]=unit["displayText"].toString()+glyph.text;unit["measuredWidth"]=glyph.x+glyph.w-unit["originX"].toDouble();result.last()=unit;}
    }return result;
}
qreal FoliaScene::progress(int i)const{return i<0||i>=lines_.size()?0:sat((position_-lines_[i].start)/std::max(100.,lines_[i].end-lines_[i].start));}
qreal FoliaScene::cameraIndex()const{
    if(current_<0)return 0;
    const qreal duration=std::min(850.,std::max(100.,(lines_[current_].end-lines_[current_].start)*.28));
    return reduced_?current_:current_-1+out((position_-lines_[current_].start)/duration);
}
void FoliaScene::compile(){
    ++geometryRevision_;camera_.valid=false;lines_.clear();if(width()<1||height()<1)return;
    QVector3D origin(0,0,0),forward(0,0,1),right(1,0,0),up(0,-1,0);
    for(int i=0;i<lyrics_.size();++i){
        const auto source=lyrics_[i].toMap();Line line;
        line.text=lineText(source);line.translation=source.value("translation",source.value("zh")).toString();line.start=FumeLayout::start(source);
        line.end=i+1<lyrics_.size()?FumeLayout::start(lyrics_[i+1].toMap()):line.start+5000;
        line.chorus=source.value("isChorus").toBool();line.shot=(int(FumeLayout::hash(seed_+QString::number(i/3)))+i%3)&0x7fffffff;
        const qreal r=randomUnit(seed_,i*7),s=randomUnit(seed_,i*7+1);
        // Parallel-transport corridor, following the upstream path-frame contract.
        if(i){const auto old=forward;forward=QQuaternion::fromAxisAndAngle(up,(r-.5)*35).rotatedVector(forward);forward=QQuaternion::fromAxisAndAngle(right,(s-.5)*22).rotatedVector(forward).normalized();const auto transport=QQuaternion::rotationTo(old,forward);right=transport.rotatedVector(right).normalized();up=transport.rotatedVector(up).normalized();origin+=forward*8;}
        line.origin=origin+right*float((r-.5)*2.4)+up*float((s-.5)*1.6);line.right=right;line.up=up;line.forward=forward;
        const qreal size=std::clamp(std::min(width()*.053,height()*.088),22.,76.);
        line.font=style_=="claddagh"?size*.9:style_=="cappella"?size*.48:style_=="monet"||style_=="pendolo"?size*.70:size;
        const auto region=composition_.value("region").toMap();
        if(style_=="tempera")line.font*=region.value("fontScale",1.).toDouble();
        QFont font(family_);font.setPixelSize(qRound(line.font));font.setWeight(style_=="tilt"?QFont::Normal:QFont::DemiBold);
        // Reserve room for individual glyph lift/scale before measuring wraps.
        // Orbit uses Folia's .04 em letters + .18 em base tracking; its local
        // focus magnification is compensated separately below.
        const qreal tracking=style_=="claddagh"?.22:style_=="classic"?.24:style_=="cadenza"?.20:style_=="tilt"?.08:.025;
        font.setLetterSpacing(QFont::AbsoluteSpacing,line.font*tracking);
        qreal lineWidth=width()*(style_=="cappella"?.5:style_=="pendolo"?.48:style_=="cadenza"?.72:.78);
        if(style_=="tempera")lineWidth=width()*region.value("w",.78).toDouble();
        if(style_=="claddagh")lineWidth=100000;
        if(style_=="partita"||style_=="tilt"||style_=="sonnet"){
            const int rowCount=line.text.size()>18?3:line.text.size()>6?2:1;
            lineWidth=std::min(lineWidth,std::max(line.font*2,QFontMetricsF(font).horizontalAdvance(line.text)/rowCount+line.font*.1));
        }
        QTextLayout layout(line.text,font);QTextOption option;option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);layout.setTextOption(option);
        layout.beginLayout();QList<QTextLine> rows;
        while(true){auto row=layout.createLine();if(!row.isValid())break;row.setLineWidth(lineWidth);row.setPosition({0,line.h});line.h+=row.height()*1.2;line.w=std::max(line.w,row.naturalTextWidth());rows.append(row);}layout.endLayout();
        // Very long lines fit as one uniformly scaled composition, keeping glyph proportions.
        const qreal fit=std::min(1.,height()*(style_=="tempera"?region.value("h",.58).toDouble():.58)/std::max(1.,line.h));line.font*=fit;line.w*=fit;line.h*=fit;
        const auto words=source.value("words").toList();
        struct Range{int begin,end;double start,finish;};QVector<Range> timing;
        int cursor=0;
        for(const auto& value:words){const auto word=value.toMap();const auto text=word.value("text").toString();if(text.isEmpty())continue;
            // Parser display strings may contain spaces absent from word timing.
            // Walk forwards only; repeated words never attach to an earlier occurrence.
            int begin=line.text.indexOf(text,cursor);if(begin<0){while(cursor<line.text.size()&&line.text[cursor].isSpace())cursor++;begin=cursor;}
            const int end=std::min(line.text.size(),begin+text.size());cursor=end;
            const qreal start=word.value("startMs",line.start).toDouble(),finish=std::max(start,word.value("endMs",start).toDouble());
            timing.append({begin,end,start,finish});line.end=std::max(line.end,finish);
        }
        QTextBoundaryFinder finder(QTextBoundaryFinder::Grapheme,line.text);int from=0,to=0,ordinal=0,group=0;
        while((to=finder.toNextBoundary())>=0){Glyph glyph;glyph.text=line.text.mid(from,to-from);glyph.ordinal=ordinal++;
            glyph.start=line.start;glyph.end=line.end;glyph.group=group;
            for(const auto& t:timing)if(from>=t.begin&&from<t.end){glyph.start=mix(t.start,t.finish,qreal(from-t.begin)/std::max(1,t.end-t.begin));glyph.end=mix(t.start,t.finish,qreal(to-t.begin)/std::max(1,t.end-t.begin));glyph.timed=t.finish>t.start;break;}
            for(int ri=0;ri<rows.size();++ri){const auto& row=rows[ri];if(from>=row.textStart()&&from<row.textStart()+row.textLength()){
                const qreal left=row.cursorToX(from),end=row.cursorToX(to);glyph.x=(std::min(left,end)+(line.w/fit-row.naturalTextWidth())/2)*fit;glyph.y=row.y()*fit;glyph.w=std::max(1.,std::abs(end-left)*fit);glyph.row=ri;break;}}
            if(!line.glyphs.isEmpty()&&line.glyphs.last().row!=glyph.row)++group;glyph.group=group;
            line.glyphs.append(glyph);if(glyph.text.trimmed().isEmpty()||glyph.text.contains(QRegularExpression("[，。！？、,.!?]"))||glyph.ordinal%4==3)++group;
            from=to;
        }
        lines_.append(line);
    }
    current_=int(std::upper_bound(lines_.cbegin(),lines_.cend(),position_,[](qreal t,const Line& l){return t<l.start;})-lines_.cbegin())-1;
    updateDioramaCamera();rebuildWindow();emit currentChanged();emit frameChanged();
}
QVariantMap FoliaScene::nodeFor(int i,int g,int kind)const{
    const auto& line=lines_[i];QVariantMap n{{"key",style_+":"+QString::number(i)+":"+QString::number(kind)+":"+QString::number(g)},{"line",i},{"glyph",g},{"kind",kind},{"fontSize",line.font},{"width",line.w+32},{"height",line.h+26}};
    if(kind==0){const auto& glyph=line.glyphs[g];n["text"]=glyph.text;n["width"]=glyph.w+2;n["height"]=line.font*1.5;n["italic"]=style_=="tilt"&&glyph.row%2==1;}
    else if(kind==2){qreal last=line.glyphs[g].x;for(const auto& glyph:line.glyphs)if(glyph.row==line.glyphs[g].row)last=std::max(last,glyph.x+glyph.w);n["width"]=last-line.glyphs[g].x+32;n["height"]=1.;}
    else if(kind==3){n["width"]=line.font*.85;n["height"]=line.font*.85;}
    return n;
}
void FoliaScene::rebuildWindow(){
    QVariantList rows;if(current_<0||lines_.isEmpty()){model_.sync(rows);return;}
    const int before=style_=="cappella"?5:style_=="pendolo"||style_=="monet"?4:style_=="diorama"?2:1;
    const int after=style_=="pendolo"||style_=="monet"?4:style_=="diorama"?3:style_=="cappella"?0:1;
    for(int i=std::max(0,current_-before);i<std::min(int(lines_.size()),current_+after+1);++i){
        if(lines_[i].text.trimmed().isEmpty())continue;
        if(style_=="cappella"){rows.append(nodeFor(i,0,1));rows.append(nodeFor(i,0,3));}
        for(int g=0;g<lines_[i].glyphs.size();++g){
            if(style_=="partita"&&(g==0||lines_[i].glyphs[g-1].row!=lines_[i].glyphs[g].row))rows.append(nodeFor(i,g,2));
            rows.append(nodeFor(i,g));
        }
    }
    model_.sync(rows);
}
qreal FoliaScene::dioramaUnit(const Line& line)const{
    const qreal unit=.68/std::max(1.,line.font);
    return unit*std::min(1.,6.5/std::max(.01,line.w*unit));
}
void FoliaScene::updateDioramaCamera(){
    camera_.valid=false;if(style_!="diorama"||lines_.isEmpty())return;
    const int b=std::clamp(current_,0,int(lines_.size())-1),a=std::max(0,b-1);
    struct Rig {QVector3D eye,target,down;qreal roll=0,distance=5.2;};
    const auto rig=[&](int index,qreal time){
        const auto& line=lines_[index];
        const qreal end=index+1<lines_.size()?lines_[index+1].start:line.end;
        const qreal p=reduced_?.5:sat((time-line.start)/std::max(100.,end-line.start));
        const qreal e=smoothStep(p),dir=randomUnit(seed_,index*17+2)<.5?-1:1;
        // Fit to the narrower field of view, including a portrait window. A
        // close shot still leaves room for the complete multi-row lyric plane.
        const qreal unit=dioramaUnit(line),tanFov=std::tan(55*pi/360.);
        const qreal fitDistance=std::max(line.w*unit/(2*tanFov*(width()/height())*.76),line.h*unit/(2*tanFov*.64));
        const qreal hero=std::max(5.2,fitDistance/.72);
        qreal back=hero,side=0,lift=.35,roll=0;
        // Folia cameraPath.resolveShotOffset, adapted to a screen-down basis.
        if(!reduced_)switch(line.shot%13){
        case 0:back=hero*(1.5-.8*e);lift=.6-.25*e;break;
        case 1:back=hero*(.85+1.15*e);lift=.5+1.7*e;break;
        case 2:{const auto theta=dir*.55*(2*e-1);side=hero*std::sin(theta);back=hero*std::cos(theta);lift=.9;break;}
        case 3:side=dir*hero*.34*std::sin(pi*p);back=hero*1.06;lift=.62;break;
        case 4:lift=dir>0?mix(-1.5,2.4,e):mix(2.4,-1.4,e);back=hero*1.05;break;
        case 5:lift=.5+.3*std::sin(p*pi);break;
        case 6:side=hero*std::sin(dir*.4*e)*1.1;back=hero*(1+.35*e);lift=.8+1.2*e;break;
        case 7:side=hero*std::sin(dir*.7*(2*e-1))*.85;back=hero*(1.05-.1*e);lift=-.3+2.4*e;roll=dir*mix(-5.,5.,e);break;
        case 8:side=dir*hero*.45*(2*e-1);lift=1.4-.9*std::sin(pi*e);back=hero*1.02;roll=dir*mix(3.,-3.,e);break;
        case 9:side=dir*hero*(.7-1.4*e);back=hero*(.78+.12*std::sin(pi*e));lift=.55;break;
        case 10:side=dir*hero*.16*std::sin(e*pi*2);lift=1.1+.5*std::sin(e*pi*2+1);back=hero*(1.05+.06*std::sin(e*pi));break;
        case 11:side=dir*hero*.22*e;lift=.5+1.4*e;back=hero*(1.15-.25*e);break;
        case 12:{const auto theta=dir*.5*std::sin(pi*e);side=hero*std::sin(theta)*1.3;back=hero*(1.05+.12*(1-std::cos(theta)));lift=.5+.5*std::sin(pi*e);break;}}
        qreal head=0;
        if(!reduced_&&timed_){
            qreal total=0;for(const auto& glyph:line.glyphs){if(!glyph.timed)continue;
                const qreal d=time<glyph.start?glyph.start-time:time>glyph.end?time-glyph.end:0;
                const qreal weight=std::exp(-d*d/245000.);head+=(glyph.x+glyph.w/2-line.w/2)*unit*weight;total+=weight;}
            head=total>0?head/total*.18:0;
        }
        const qreal clock=reduced_?0:time/1000.,phase=randomUnit(seed_,91)*pi*2;
        const qreal drift=reduced_?0:std::sin(clock*.17+phase)*.10;
        Rig result;result.target=line.origin+line.right*float(head);
        result.eye=result.target-line.forward*float(back)+line.right*float(side+drift)-line.up*float(lift);
        result.down=line.up;result.roll=roll;result.distance=back;return result;
    };
    const auto incoming=rig(b,position_);auto shot=incoming;
    if(a!=b&&!reduced_){
        // Evaluate the outgoing shot at the exact boundary, not at the new
        // line's progress. This removes the old discontinuity in side/roll.
        const auto outgoing=rig(a,lines_[b].start);
        const qreal end=b+1<lines_.size()?lines_[b+1].start:lines_[b].end;
        const qreal duration=std::min(1400.,std::max(80.,(end-lines_[b].start)*.38));
        const qreal t=smoothStep((position_-lines_[b].start)/duration);
        const qreal arc=std::sin(pi*t)*std::sin(pi*t);
        shot.eye=outgoing.eye*(1-t)+incoming.eye*t-lines_[b].up*float(arc*.42);
        shot.target=outgoing.target*(1-t)+incoming.target*t;
        shot.down=(outgoing.down*(1-t)+incoming.down*t).normalized();
        shot.roll=mix(outgoing.roll,incoming.roll,t);shot.distance=mix(outgoing.distance,incoming.distance,t);
    }
    auto& camera=camera_;camera.eye=shot.eye;camera.forward=(shot.target-shot.eye).normalized();
    const auto right=QVector3D::crossProduct(camera.forward,shot.down).normalized();
    const auto down=QVector3D::crossProduct(right,camera.forward).normalized();
    const qreal roll=shot.roll*pi/180.;
    camera.right=right*float(std::cos(roll))-down*float(std::sin(roll));
    camera.down=right*float(std::sin(roll))+down*float(std::cos(roll));
    camera.focal=height()/(2*std::tan(55*pi/360.));camera.distance=shot.distance;
    camera.view.setRow(0,QVector4D(camera.right,-QVector3D::dotProduct(camera.right,camera.eye)));
    camera.view.setRow(1,QVector4D(camera.down,-QVector3D::dotProduct(camera.down,camera.eye)));
    camera.view.setRow(2,QVector4D(camera.forward,-QVector3D::dotProduct(camera.forward,camera.eye)));
    camera.view.setRow(3,QVector4D(0,0,0,1));camera.valid=true;
}
QVariantMap FoliaScene::inspectCamera()const{
    if(!camera_.valid)return {};
    return {{"eye",QVariant::fromValue(camera_.eye)},{"right",QVariant::fromValue(camera_.right)},
        {"down",QVariant::fromValue(camera_.down)},{"forward",QVariant::fromValue(camera_.forward)},
        {"view",QVariant::fromValue(camera_.view)},{"focal",camera_.focal}};
}
FoliaPose FoliaScene::dioramaPose(const QVariantMap& node)const{
    FoliaPose pose;if(!camera_.valid){pose.alpha=0;return pose;}
    const int i=node.value("line").toInt(),g=node.value("glyph").toInt();const auto& line=lines_[i];const auto& glyph=line.glyphs[g];
    const auto& camera=camera_;const qreal unit=dioramaUnit(line);
    const auto world=line.origin+line.right*float((glyph.x+glyph.w/2-line.w/2)*unit)+line.up*float((glyph.y+line.font*.7-line.h/2)*unit);
    const auto relative=world-camera.eye;const qreal z=QVector3D::dotProduct(relative,camera.forward);
    if(z<=.3){pose.alpha=0;return pose;}
    const qreal focal=camera.focal;const QPointF screen(QVector3D::dotProduct(relative,camera.right)*focal/z,QVector3D::dotProduct(relative,camera.down)*focal/z);
    pose.x=width()/2+screen.x()-glyph.w/2;pose.y=height()*.47+screen.y()-line.font*.7;
    pose.scale=unit*focal/z;pose.depth=-z;
    pose.alpha=smoothStep((40-z)/8)*smoothStep((z-.9)/1.1)*(i==current_?1:.23);
    pose.defocus=i==current_?0:std::min(8.,std::abs(z-camera.distance)*.5);
    pose.yaw=std::asin(std::clamp(qreal(QVector3D::dotProduct(line.right,camera.forward)),-1.,1.))*180/pi;
    pose.pitch=-std::asin(std::clamp(qreal(QVector3D::dotProduct(line.up,camera.forward)),-1.,1.))*180/pi;
    pose.rotation=std::atan2(QVector3D::dotProduct(line.right,camera.down),QVector3D::dotProduct(line.right,camera.right))*180/pi;
    const bool timed=timed_&&glyph.timed;const qreal glow=timed?envelope(position_,glyph.start,glyph.end):1.;
    pose.light=glow;pose.alpha*=timed?(.5+.5*smoothStep((position_-glyph.start)/160.)):1.;
    const qreal after=position_-glyph.end;
    // Upstream soul hand-off: no detached copy while the word is still sung.
    if(timed&&after>=0&&!reduced_){const qreal flight=smoothStep(after/500.);pose.ghost=.6*std::exp(-after/600.)*flight;pose.lift=-line.font*.5*flight;pose.ghostScale=1+.3*flight;}
    const qreal reveal=timed?smoothStep((position_-glyph.start)/140.):1.;
    pose.color=blendColor(QColor("#f2eee9"),accent_,reveal*.88,1.);return pose;
}
FoliaPose FoliaScene::pose(const QVariantMap& n)const{
    FoliaPose v;const int i=n.value("line").toInt(),gi=n.value("glyph").toInt(),kind=n.value("kind").toInt();
    if(i<0||i>=lines_.size()||current_<0){v.alpha=0;return v;}
    const auto& l=lines_[i];if(gi>=l.glyphs.size()){v.alpha=0;return v;}const auto& g=l.glyphs[gi];
    if(style_=="diorama")return dioramaPose(n);
    const bool timed=timed_&&g.timed;const qreal p=progress(i),age=position_-l.start,wordAge=position_-(timed?g.start:l.start);
    const qreal pulse=timed?envelope(position_,g.start,g.end):0,entered=out(wordAge/350.),passed=timed?smoothStep((position_-g.end)/1800.):0;
    const qreal phase=reduced_||style_=="still"?qreal(current_):cameraIndex(),d=i-phase;
    qreal x=g.x-l.w/2,y=g.y-l.h/2,scale=1,angle=0;v.light=pulse;
    v.alpha=i==current_?(.42+.58*(timed?smoothStep(wordAge/150.):1)):.25;
    const qreal r=randomUnit(seed_+l.text,g.group*19+1),r2=randomUnit(seed_+l.text,g.ordinal*13+7);
    if(style_=="claddagh"){
        const qreal radius=orbitRadius(width(),energy_),minor=radius*.09;
        // The source's near-side enlargement needs matching arc advance for
        // wide CJK glyphs. Expand the measured arc, then fit long lines as a
        // whole; glyph proportions and the elliptical depth remain intact.
        const qreal spacing=1.48;
        const qreal span=std::min(1.,4.25/std::max(.01,l.w*spacing/radius));
        const auto& active=lines_[current_];
        const auto readOffset=[&](const Line& line){
            if(line.glyphs.isEmpty())return qreal(0);
            if(!timed_||!line.glyphs.first().timed){
                const qreal offset=mix(line.glyphs.first().x+line.glyphs.first().w/2,line.glyphs.last().x+line.glyphs.last().w/2,
                    sat((position_-line.start)/std::max(100.,line.end-line.start)));
                return (offset-line.w/2)*spacing/radius*std::min(1.,4.25/std::max(.01,line.w*spacing/radius));
            }
            qreal offset=line.glyphs.last().x+line.glyphs.last().w/2;
            for(int j=0;j<line.glyphs.size();++j){const auto& c=line.glyphs[j];if(position_>=c.end)continue;
                const auto& next=line.glyphs[std::min(j+1,int(line.glyphs.size())-1)];
                offset=mix(c.x+c.w/2,next.x+next.w/2,sat((position_-c.start)/std::max(100.,c.end-c.start)));break;}
            return (offset-line.w/2)*spacing/radius*std::min(1.,4.25/std::max(.01,line.w*spacing/radius));
        };
        const qreal backFollow=i<current_?0:i>current_?1:sat(std::abs(d));
        const qreal wordOffset=readOffset(l)+(readOffset(active)*.28+pi*.52*(1-std::pow(1-progress(current_),1.35)))*backFollow;
        const qreal psi=d*pi+(g.x+g.w/2-l.w/2)*spacing/radius*span-wordOffset;
        const qreal depth=(std::cos(psi)+1)/2,f=std::pow(sat(1-std::abs(psi)/.48),1.8)*sat(1-std::abs(d));
        const auto point=orbitPoint(radius,psi);
        x=point.x()-g.w/2;y=point.y()-l.font*.6;
        angle=std::atan2(-std::sin(psi)*minor,std::cos(psi)*radius)*180/pi-45;
        while(angle>90)angle-=180;while(angle< -90)angle+=180;angle=std::clamp(angle*(.4+.6*depth),-38.,38.);
        scale=(.22+.98*std::pow(depth,1.5))*(1+.65*f)*span;
        v.alpha=(.35+.65*std::pow(depth,1.5)*(.35+.65*f))*(.68+.32*std::pow(depth,1.9))*sat(2-std::abs(d));
        if(i<current_)v.alpha*=sat(1-std::abs(d));if(i>current_)v.alpha*=.18+.82*smoothStep((position_-lines_[current_].end+340)/340.);
        if(std::abs(d)>.02){const qreal threshold=1-1.2*sat((std::abs(d)-.3)/.6);v.alpha*=sat(1-(std::cos(psi)-threshold)/.15);}
        if(i>current_&&active.glyphs.size()>10){const qreal mitigation=sat((active.glyphs.size()-10)/8.)*std::clamp((l.glyphs.size()-5)/5.,.4,1.)*sat((std::abs(d)-.4)/.5);v.alpha*=1-mitigation;scale*=1-mitigation*.25;}
        v.defocus=8*(1-depth)*(1-.5*f);
        v.depth=depth;v.light=pulse*f;
        // Folia's timed snap: the glyph crosses the fixed normal and becomes
        // the accent in the first 1/15 of its interval. Untimed lines use the
        // geometric read-head position instead of staying stationary/white.
        const qreal tint=timed?sat((position_-g.start)/std::max(1.,(g.end-g.start)/15.)):
            (i<current_?1:i>current_?0:sat(-psi/.025));
        v.color=blendColor(QColor("#faf7f2"),accent_,tint,mix(.55,.92,tint));
    }else if(style_=="pendolo"){
        const qreal radius=std::min(width(),height())*.42;
        angle=d*12.5;const qreal a=angle*pi/180.;
        scale=i==current_?1.16:std::max(.7,1-std::abs(d)*.08);
        const auto point=rotated(radius+g.x*scale,(g.y-l.h/2)*scale,a);x=-width()/2+point.x();y=point.y();
        v.alpha=std::abs(a)>=pi/2?0:std::max(.08,std::pow(std::max(0.,std::cos(a*.75)),2.5)*(1-std::abs(d)*.18));
        v.alpha*=i==current_?(.4+.6*(timed?smoothStep(wordAge/130.):1)):.55;
    }else if(style_=="cappella"){
        qreal offset=0;if(i<current_)for(int j=i+1;j<=current_;++j)offset+=lines_[j].h+54;
        if(i<current_&&!reduced_)offset-=(1-out((position_-lines_[current_].start)/550.))*(lines_[current_].h+54);
        const bool right=i%4==3;const qreal bx=right?width()*.77-l.w:width()*.23;
        x=bx-width()/2+g.x;y=height()*.18-offset+g.y;
        const qreal rise=reduced_?1:out(age/500.);y+=(1-rise)*34;
        v.alpha=smoothStep((height()*.47+y+80)/80.)*(i==current_?1:.62);
        if(timed)v.alpha*=out((wordAge+60)/220.);
        if(kind==1){x=bx-width()/2-16;y=height()*.18-offset-13+(1-rise)*34;v.alpha=.94;v.color=QColor(right?"#557966":"#3a4556");v.depth=-2;}
        if(kind==3){x=bx-width()/2+(right?l.w+26:-l.font*.85-26);y=height()*.18-offset;v.color=QColor::fromHslF(randomUnit(seed_,i*6),.32,.67);v.alpha=.9;}
    }else if(style_=="monet"||style_=="still"){
        scale=i==current_?1:std::max(.68,.86-std::abs(d)*.06);
        x=(g.x+g.w/2-l.w/2)*scale-g.w/2;
        y+=d*std::min(height()*.18,125.);
        v.alpha=i==current_?(.45+.55*(timed?smoothStep(wordAge/220.):1)):std::max(.12,.5-std::abs(d)*.09);
        if(style_=="monet"){v.color=QColor::fromHslF(.10+r*.58,.28,.87);y-=reduced_?0:pulse*3;v.defocus=std::min(7.,std::abs(d)*1.4);}
        else {v.alpha=i==current_?1:.3;v.light=0;}
    }else if(style_=="partita"){
        const qreal rowOffset=(g.row%2?1:-1)*width()*.10;
        x+=rowOffset;y+=g.row*l.font*.22;
        if(!reduced_){x+=(1-entered)*(g.row%2?60:-60);y+=(1-entered)*20-pulse*10;angle=(r-.5)*8*(1-entered);scale=.88+.12*entered+pulse*.04;}
        v.alpha*=i==current_?smoothStep((age+100)/260.):(1-smoothStep(std::abs(d)))*.4;
        if(kind==2){x=g.x-l.w/2+rowOffset-16;y=g.y-l.h/2+(g.row+1)*l.font*.22+l.font*1.25;scale=1;angle=0;v.alpha=.22*(i==current_?entered:0);v.color=QColor("#bccddc");}
    }else if(style_=="tilt"){
        const bool tilt=g.row%2==1;
        x+=(g.row%2?1:-1)*l.font*.6;y+=g.row*l.font*.1;
        if(tilt){angle=-6;const auto xy=rotated(x,y,-6*pi/180.);x=xy.x();y=xy.y()+(g.ordinal%2?1:-1)*l.font*.09;}
        if(!reduced_){y+=(1-out((age-g.ordinal*35)/500.))*25;scale=1+pulse*(tilt?.18:.15);}
        v.color=tilt?QColor("#e3be9c"):QColor("#f4f2ed");v.alpha*=i==current_?smoothStep((age-g.ordinal*28)/300.):0;
    }else if(style_=="cadenza"){
        const qreal entry=out(wordAge/420.),exit=smoothStep((position_-l.end)/300.);
        const qreal track=.04+(reduced_?0:passed*.12);x+=(g.x-l.w/2)*track;
        if(!reduced_){x+=(1-entry)*(r-.5)*80;y+=(1-entry)*40-pulse*l.font*.09+(r2-.5)*passed*l.font*.15;scale=mix(.5,1,entry)+pulse*.3;angle=(1-entry)*20+(r-.5)*8*passed;}
        v.alpha=(i<=current_?1:0)*entry*(1-exit)*(.82+.18*pulse);
        v.defocus=reduced_?0:10*(1-entry)+10*exit;
        v.ghost=reduced_?0:pulse*.20;v.lift=0;v.ghostScale=1.04;
    }else if(style_=="sonnet"){
        const int shot=l.shot%7;const qreal direction=g.row%2?-1:1;
        if(shot==0){x=(g.row-(std::ceil(l.h/(l.font*1.2))-1)/2)*l.font*1.4;y=(g.x-l.w/2)*.8;}
        else if(shot==1){scale=1.28;x*=1.05;y*=1.05;}
        else if(shot==2){x+=direction*l.font*.65;y+=std::sin(g.group*1.7)*l.font*.3;angle=direction*6;}
        else if(shot==3){const auto xy=rotated(x,y,-.13);x=xy.x()-(p-.5)*width()*.12;y=xy.y();angle=-7.45;}
        else if(shot==4){y+=g.row*l.font*.15;}
        else if(shot==5){scale=g.row==0?1.3:.86;x+=direction*l.font*.85;y+=g.row*l.font*.3;}
        else {scale=.85;y+=g.row*l.font*.1;}
        for(const auto& value:placements_){const auto box=value.toMap();if(box.value("group").toInt()!=g.group)continue;
            scale=box.value("fontScale",1).toDouble();const qreal localX=(g.x-box.value("originX").toDouble())*scale-box.value("measuredWidth").toDouble()/2;
            const qreal localY=(g.y-box.value("originY").toDouble())*scale-l.font*scale*.6;
            angle=box.value("rotation",0).toDouble()*180/pi;
            const auto placed=rotated(localX,localY,angle*pi/180.);x=box.value("x").toDouble()+placed.x();y=box.value("y").toDouble()+placed.y();break;
        }
        const qreal enter=1-std::pow(2,-10*sat((wordAge+100)/480.));
        if(!reduced_){x+=(1-enter)*direction*l.font*.55;y+=(1-enter)*l.font*.4;scale*=1+(1-enter)*(shot==1?.7:.12)+pulse*.05;angle+=(1-enter)*(r-.5)*28;}
        v.alpha=(i==current_?1:0)*smoothStep((wordAge+100)/180.);v.color=g.group%3==0?QColor("#e5bd92"):QColor("#f5f0e6");
    }else if(style_=="tempera"){
        const int enterStyle=g.group%7;const auto region=composition_.value("region").toMap();
        const auto camera=composition_.value("camera").toMap();
        angle=region.value("rotation",0.).toDouble()*180/pi;
        const auto rotatedText=rotated(x,y,angle*pi/180.);x=rotatedText.x();y=rotatedText.y();
        x+=(region.value("cx",.5).toDouble()-.5)*width();y+=(region.value("cy",.5).toDouble()-.47)*height();
        if(!reduced_){const qreal travel=camera.value("travel",.08).toDouble()*height()*p*.3;y-=travel;}
        const qreal enter=out(wordAge/std::clamp(l.end-(timed?g.start:l.start),400.,2400.)),travel=1-enter;
        const qreal release=smoothStep((position_-(timed?g.end:l.end))/std::max(300.,l.end-g.end));
        if(!reduced_){
            qreal dx=0,dy=1;switch(enterStyle){case 0:dx=.7;dy=.7;break;case 1:dx=-1;dy=.12;break;case 2:dx=1;dy=-.12;break;case 3:dx=.12;dy=-1;break;case 4:dx=-.12;dy=1;break;case 5:dx=.6;dy=.6;angle+=travel*54;break;case 6:dx=dy=0;scale*=1+travel*.7;break;}
            x+=dx*l.font*.8*travel+(g.x-l.w/2)*release*.055;y+=dy*l.font*.8*travel;
            scale*=1+pulse*.05;v.ghost=enterStyle==6?0:.24*travel*smoothStep(wordAge/120.);v.lift=-dy*l.font*.10*travel;v.ghostScale=1;
        }
        v.alpha=(i==current_?1:0)*smoothStep(wordAge/std::min(550.,std::max(100.,l.end-l.start)*.2));v.color=QColor("#f7f1e7");
    }else {
        // Folia classic: word body springs in, its glow scans by grapheme,
        // then the readable body settles while the preceding line dissolves.
        const qreal entry=out(wordAge/360.),exit=smoothStep((position_-l.end)/300.);
        if(!reduced_){x+=(r-.5)*55*(1-entry);y+=(1-entry)*32-pulse*9-passed*(r2-.5)*8;angle=(r-.5)*5+20*(1-entry)+(r2-.5)*4*passed;scale=.5+.5*entry+pulse*.28+.1*exit;}
        v.alpha=(i<=current_?1:0)*smoothStep(wordAge/100.)*(1-exit)*(.82+.18*pulse);
        v.defocus=reduced_?0:10*(1-entry)+10*exit;
    }
    if(reduced_){v.ghost=0;v.defocus=0;v.light=timed?smoothStep(wordAge/150.):1;}
    v.x=width()/2+x;v.y=height()*.47+y;v.scale=scale;v.rotation=angle;v.alpha=sat(v.alpha);return v;
}
QVariantMap FoliaScene::inspectPose(int line,int glyph)const{if(line<0||line>=lines_.size()||glyph<0||glyph>=lines_[line].glyphs.size())return {};const auto v=pose(nodeFor(line,glyph));return {{"x",v.x},{"y",v.y},{"scale",v.scale},{"alpha",v.alpha},{"rotation",v.rotation},{"ghost",v.ghost},{"glyphs",lines_[line].glyphs.size()},{"shot",shotName()}};}
FoliaNodeItem::FoliaNodeItem(QQuickItem* parent):QQuickItem(parent),plane_(this){plane_.appendToItem(this);}
void FoliaNodeItem::setScene(FoliaScene* value){if(scene_==value)return;if(scene_)disconnect(scene_,nullptr,this,nullptr);scene_=value;if(scene_)connect(scene_,&FoliaScene::frameChanged,this,&FoliaNodeItem::advance);emit sceneChanged();advance();}
void FoliaNodeItem::setNode(const QVariantMap& value){node_=value;emit nodeChanged();advance();}
void FoliaNodeItem::advance(){if(!scene_||node_.isEmpty())return;const auto p=scene_->pose(node_);setX(p.x);setY(p.y);setScale(p.scale);setRotation(p.rotation);setZ(p.depth);setOpacity(p.alpha);plane_.setPlane(p.pitch,p.yaw,width(),height());
    if(p.light!=paint_.light||p.ghost!=paint_.ghost||p.lift!=paint_.lift||p.ghostScale!=paint_.ghostScale||p.color!=paint_.color||p.defocus!=paint_.defocus){paint_=p;emit paintChanged();}}
void FoliaPlaneTransform::setPlane(qreal pitch,qreal yaw,qreal w,qreal h){QMatrix4x4 m;m.translate(w/2,h/2);m.rotate(yaw,0,1,0);m.rotate(pitch,1,0,0);m.translate(-w/2,-h/2);if(m!=matrix_){matrix_=m;update();}}
QSGNode* ImmersiveSpectrumItem::updatePaintNode(QSGNode* old,UpdatePaintNodeData*){
    constexpr int count=32;auto* node=static_cast<QSGGeometryNode*>(old);
    if(!node){node=new QSGGeometryNode;auto* geo=new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(),count*6);geo->setDrawingMode(QSGGeometry::DrawTriangles);geo->setVertexDataPattern(QSGGeometry::DynamicPattern);node->setGeometry(geo);node->setFlag(QSGNode::OwnsGeometry);node->setMaterial(new QSGVertexColorMaterial);node->setFlag(QSGNode::OwnsMaterial);}
    auto* vertices=node->geometry()->vertexDataAsColoredPoint2D();const qreal cell=width()/count,bar=std::max(1.,cell-2);
    for(int i=0;i<count;++i){const qreal sample=qreal(i)*31/(count-1);const int a=int(sample),b=std::min(31,a+1);const qreal value=mix(bands_.value(a).toDouble(),bands_.value(b).toDouble(),sample-a);const float left=i*cell+(cell-bar)/2,right=left+bar,bottom=height(),top=height()-std::max(0.,value*height());
        const auto put=[&](int v,float x,float y,bool lower){const int alpha=lower?170:45;vertices[i*6+v].set(x,y,180*alpha/255,213*alpha/255,244*alpha/255,alpha);};put(0,left,top,false);put(1,right,top,false);put(2,left,bottom,true);put(3,right,top,false);put(4,right,bottom,true);put(5,left,bottom,true);}
    node->markDirty(QSGNode::DirtyGeometry);return node;
}
void FoliaDecorItem::setScene(FoliaScene* value){if(scene_==value)return;if(scene_)disconnect(scene_,nullptr,this,nullptr);scene_=value;if(scene_)connect(scene_,&FoliaScene::frameChanged,this,[this]{update();});update();emit sceneChanged();}
QSGNode* FoliaDecorItem::updatePaintNode(QSGNode* old,UpdatePaintNodeData*){
    if(scene_&&scene_->style_=="diorama"){
        auto* node=dynamic_cast<diorama::Node*>(old);if(!node){delete old;node=new diorama::Node;}
        const auto& s=*scene_;const int focus=std::max(0,s.current_);
        const int first=std::max(0,focus-2),last=std::min(int(s.lines_.size())-1,focus+4);
        const QSizeF size(width(),height());
        if(node->owner!=scene_||node->revision!=s.geometryRevision_||node->first!=first||node->last!=last||node->size!=size){
            node->owner=scene_;node->revision=s.geometryRevision_;node->first=first;node->last=last;node->size=size;
            QVector<diorama::Particle> points;points.reserve(24000);
            struct Cluster {diorama::Shape shape;QVector3D anchor;int line;};QVector<Cluster> candidates;
            // Include two predecessors for stable cross-line clearance. Every
            // candidate tests the same earlier anchors regardless of the
            // mounted window; seeking cannot reshuffle a visible formation.
            for(int i=std::max(0,first-2);i<=last;++i){const auto& l=s.lines_[i];
                const auto shapes=diorama::formation(l.shot,FumeLayout::hash(s.seed_+QString::number(i)),l.w*s.dioramaUnit(l)/2);
                for(const auto& shape:shapes){const auto p=shape.center;
                    candidates.append({shape,l.origin+l.right*p.x()+l.up*p.y()+l.forward*p.z(),i});}
            }
            for(int c=0;c<candidates.size();++c){const auto& cluster=candidates[c];if(cluster.line<first)continue;
                const auto& shape=cluster.shape;bool hidden=false;
                const auto radius=[](const diorama::Shape& shape){return shape.scale*std::max(.8,shape.stretch*.55)*1.18;};
                for(int earlier=0;earlier<c;++earlier){const auto& other=candidates[earlier];
                    if(other.line>=cluster.line||other.line<cluster.line-2)continue;
                    if((cluster.anchor-other.anchor).length()<(radius(shape)+radius(other.shape))*1.12){hidden=true;break;}}
                if(hidden)continue;
                const auto& l=s.lines_[cluster.line];const auto spin=QQuaternion::fromAxisAndAngle(QVector3D(0,1,0),shape.phase*180/pi);
                const auto surface=diorama::surface(shape.kind,shape.stretch);
                for(const auto& point:surface){const auto p=spin.rotatedVector(point)*float(shape.scale);
                    points.append({l.right*p.x()+l.up*p.y()+l.forward*p.z(),cluster.anchor,shape.phase,shape.color});}
            }
            node->upload(points);
        }
        auto* material=static_cast<diorama::Material*>(node->material());material->view=s.camera_.view;
        material->viewport=QVector4D(width(),height(),s.camera_.focal,s.position_/1000.);
        material->controls=QVector4D(s.camera_.valid?s.energy_:0,s.reduced_?0:1,s.camera_.distance,1);
        material->accent=QVector4D(s.accent_.redF(),s.accent_.greenF(),s.accent_.blueF(),1);
        material->focusRect=QVector4D(-10000,-10000,1,1);
        if(s.current_>=0&&s.camera_.valid){const auto& l=s.lines_[s.current_];const qreal unit=s.dioramaUnit(l);QRectF bounds;
            bool valid=true;
            for(int corner=0;corner<4;++corner){const auto world=l.origin+l.right*float((corner%2?1:-1)*l.w*unit/2)+l.up*float((corner/2?1:-1)*l.h*unit/2);
                const auto point=s.camera_.view*QVector4D(world,1);if(point.z()<.9){valid=false;break;}
                const QPointF screen(width()*.5+point.x()*s.camera_.focal/point.z(),height()*.47+point.y()*s.camera_.focal/point.z());
                if(!corner)bounds=QRectF(screen,QSizeF(.01,.01));else bounds=bounds.united(QRectF(screen,QSizeF(.01,.01)));}
            if(valid)material->focusRect=QVector4D(float(bounds.center().x()),float(bounds.center().y()),float(bounds.width()/2+20),float(bounds.height()/2+18));
        }
        node->markDirty(QSGNode::DirtyMaterial);return node;
    }
    if(dynamic_cast<diorama::Node*>(old)){delete old;old=nullptr;}
    auto* node=static_cast<QSGGeometryNode*>(old);if(!node){node=new QSGGeometryNode;node->setGeometry(new QSGGeometry(QSGGeometry::defaultAttributes_ColoredPoint2D(),0));node->geometry()->setDrawingMode(QSGGeometry::DrawTriangles);node->setFlag(QSGNode::OwnsGeometry);node->setMaterial(new QSGVertexColorMaterial);node->setFlag(QSGNode::OwnsMaterial);}
    struct Vertex{float x,y;unsigned char r,g,b,a;};QVector<Vertex> vertices;vertices.reserve(18000);
    const auto triangle=[&](QPointF a,QPointF b,QPointF c,QColor color){const int alpha=color.alpha();for(const auto& p:{a,b,c})vertices.append({float(p.x()),float(p.y()),(unsigned char)(color.red()*alpha/255),(unsigned char)(color.green()*alpha/255),(unsigned char)(color.blue()*alpha/255),(unsigned char)alpha});};
    const auto line=[&](QPointF a,QPointF b,qreal thick,QColor color){const auto delta=b-a;const qreal length=std::hypot(delta.x(),delta.y());if(length<.01)return;const QPointF n(-delta.y()/length*thick/2,delta.x()/length*thick/2);triangle(a+n,b+n,a-n,color);triangle(b+n,b-n,a-n,color);};
    const auto softLine=[&](QPointF a,QPointF b,qreal thick,QColor color){
        const auto delta=b-a;const qreal length=std::hypot(delta.x(),delta.y());if(length<.01)return;
        const QPointF unit(-delta.y()/length,delta.x()/length),inner=unit*(thick/2),outer=unit*(thick/2+.65);
        line(a,b,thick,color);
        const auto vertex=[&](QPointF point,int alpha){vertices.append({float(point.x()),float(point.y()),(unsigned char)(color.red()*alpha/255),(unsigned char)(color.green()*alpha/255),(unsigned char)(color.blue()*alpha/255),(unsigned char)alpha});};
        for(int side:{-1,1}){const auto ai=a+inner*side,bi=b+inner*side,ao=a+outer*side,bo=b+outer*side;
            vertex(ai,color.alpha());vertex(bi,color.alpha());vertex(ao,0);vertex(bi,color.alpha());vertex(bo,0);vertex(ao,0);}
    };
    if(scene_&&scene_->current_>=0){
        const auto& s=*scene_;const qreal w=width(),h=height();const auto style=s.style_;
        if(style=="claddagh"){
            const qreal radius=orbitRadius(w,s.energy_);const QPointF center(w/2,h*.47);
            // Perpendicular to the foreground tangent (-45 degrees), with
            // faded ends and a narrow anti-aliased core behind the active word.
            const auto focus=orbitPoint(radius,0)+center;const QPointF normal=rotated(0,1,-pi/4);
            const qreal power=s.reduced_?0:s.energy_,extent=std::min(320.,h*.38)*(1+power*power*.7);
            for(int segment=0;segment<80;++segment){const qreal a=qreal(segment)/80,b=qreal(segment+1)/80,t=(a+b)/2;
                const qreal fade=smoothStep(std::min(t,1-t)/.24);
                const auto ink=blendColor(QColor("#eee9e5"),s.accent_,sat(power*1.7),(.28+.5*power)*fade);
                softLine(focus+normal*((a-.5)*extent),focus+normal*((b-.5)*extent),2.2+power*.8,ink);
            }
        }else if(style=="pendolo"){
            const qreal r=std::min(w,h)*.36;
            for(int k=-70;k<=70;k++){const qreal a=k*pi/90.,radius=r*(k%5==0?.91:.96);line({std::cos(a)*radius,h*.47+std::sin(a)*radius},{std::cos(a)*r,h*.47+std::sin(a)*r},k%5==0?1.2:.6,QColor(210,225,232,k%5==0?65:30));}
            const qreal angle=s.reduced_?0:std::sin(s.position_/1000.*2)*.08;line({0,h*.47},{std::cos(angle)*r*.85,h*.47+std::sin(angle)*r*.85},1.3,QColor(221,225,230,55));
        }else if(style=="sonnet"){
            const int kind=s.lines_[s.current_].shot%7;const qreal p=s.progress(s.current_),enter=s.reduced_?1:out(p*5);QColor ink(214,203,184,int(75*enter));
            for(int i=0;i<4;i++){const qreal x=i%2?w*.91:w*.09,y=i/2?h*.87:h*.13;line({x,y},{x+(i%2?-1:1)*w*.04,y},1,ink);line({x,y},{x,y+(i/2?-1:1)*h*.06},1,ink);}
            if(kind==1||kind==2||kind==5){const qreal radius=std::min(w,h)*.35;QPointF prev;
                for(int k=0;k<=100;k++){const qreal a=k*pi/50+(s.reduced_?0:p*.1);QPointF point;if(kind==2){const auto xy=rotated(std::cos(a)*radius,std::sin(a)*radius,.12);point=xy+QPointF(w*.5,h*.47);}else point={w*.5+std::cos(a)*radius,h*.47+std::sin(a)*radius};if(k)line(prev,point,.7,QColor(220,212,188,34));prev=point;}
            }else if(kind==0||kind==4){line({w*.23,h*.14},{w*.23,h*.79},.8,ink);line({w*.77,h*.14},{w*.77,h*.79},.8,ink);}
        }
    }
    auto* geometry=node->geometry();geometry->allocate(vertices.size());auto* data=geometry->vertexDataAsColoredPoint2D();for(int i=0;i<vertices.size();++i){const auto& v=vertices[i];data[i].set(v.x,v.y,v.r,v.g,v.b,v.a);}node->markDirty(QSGNode::DirtyGeometry);return node;
}
