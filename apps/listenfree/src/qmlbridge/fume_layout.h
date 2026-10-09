#pragma once
#include <QObject>
#include <QVariantList>
#include <QTextLayout>
#include <QTextBoundaryFinder>
#include <QFontMetricsF>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>

// Folia Fume's seeded article / shortest-column placement, adapted to Qt text
// metrics and mixed writing directions. See research/fume-typography-2026-09-10.
// Only metadata crosses QML; visible blocks own the actual Text nodes.
class FumeLayout : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList lyrics READ lyrics WRITE setLyrics NOTIFY layoutChanged)
    Q_PROPERTY(QVariantList blocks READ blocks NOTIFY layoutChanged)
    Q_PROPERTY(QString seed READ seed WRITE setSeed NOTIFY layoutChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY layoutChanged)
public:
    explicit FumeLayout(QObject* parent=nullptr):QObject(parent){}
    QVariantList lyrics() const{return lyrics_;}
    QVariantList blocks() const{return blocks_;}
    QString seed() const{return seed_;}
    QString fontFamily() const{return family_;}
    void setLyrics(const QVariantList& v){if(v==lyrics_)return;lyrics_=v;rebuild();}
    void setSeed(const QString& v){if(v==seed_)return;seed_=v;rebuild();}
    void setFontFamily(const QString& v){if(v==family_)return;family_=v;rebuild();}
    Q_INVOKABLE QVariantMap block(int index) const{return index>=0&&index<blocks_.size()?blocks_[index].toMap():QVariantMap{};}
    static uint hash(const QString& text){uint h=2166136261u;for(const QChar c:text){h^=c.unicode();h*=16777619u;}return h;}
    static qreal start(const QVariantMap& line){return line.value("timeMs",line.value("timestampMs",line.value("time",0))).toDouble();}
Q_SIGNALS:
    void layoutChanged();
private:
    struct Grapheme {QString text;int begin,end;};
    QVariantList lyrics_,blocks_;
    QString seed_,family_="Microsoft YaHei UI";
    static QList<Grapheme> graphemes(const QString& text) {
        QList<Grapheme> result;
        QTextBoundaryFinder finder(QTextBoundaryFinder::Grapheme,text);
        int from=0,to=0;
        while((to=finder.toNextBoundary())>=0) {result.append({text.mid(from,to-from),from,to});from=to;}
        return result;
    }
    static QString upright(const QString& text) {
        // Unicode vertical forms keep brackets and pauses upright.
        const QString horizontal=QStringLiteral("，、。！？：；（）［］「」『』…—");
        const QString vertical=QStringLiteral("︐︑︒︕︖︓︔︵︶﹇﹈﹁﹂﹃﹄︙︱");
        const int index=text.size()==1?static_cast<int>(horizontal.indexOf(text)):-1;
        return index>=0?QString(vertical[index]):text;
    }
    void rebuild() {
        blocks_.clear();
        QList<int> order;
        for(int i=0;i<lyrics_.size();++i) {
            const auto line=lyrics_[i].toMap();
            blocks_.append(QVariantMap{{"index",i},{"start",start(line)},{"end",start(line)},{"width",0},{"height",0}});
            if(!line.value("text",line.value("en")).toString().trimmed().isEmpty())order.append(i);
        }
        std::stable_sort(order.begin(),order.end(),[&](int a,int b) {
            const auto key=[&](int i){return hash(seed_+":"+QString::number(i)+":"+lyrics_[i].toMap().value("text").toString());};
            return key(a)<key(b);
        });
        // Fine columns let upright phrases share the skyline with wide titles.
        constexpr int columns=24;
        constexpr qreal pitch=70,gutter=20;
        std::array<qreal,columns> bottoms{};
        for(int ordinal=0;ordinal<order.size();++ordinal) {
            const int index=order[ordinal];const auto line=lyrics_[index].toMap();
            const QString text=line.value("text",line.value("en")).toString();
            const auto letters=graphemes(text);const auto words=line.value("words").toList();
            const uint variation=hash(seed_+":"+QString::number(index)+":"+text);
            int cjk=0,visible=0;
            for(const auto& letter:letters) {
                if(letter.text.trimmed().isEmpty())continue;
                ++visible;
                const auto code=letter.text.toUcs4().value(0);
                if((code>=0x2e80 && code<=0x9fff)||(code>=0xac00 && code<=0xd7af)||(code>=0x20000 && code<=0x323af))++cjk;
            }
            const bool hero=(visible<=28 && ((ordinal+1)%6==0 || line.value("isChorus").toBool()))
                || ordinal==order.size()/2;
            const bool verticalSlot=(ordinal+static_cast<int>(hash(seed_)%4))%4==1;
            const bool vertical=verticalSlot && cjk*5>=visible*3 && visible>=3 && visible<=24;
            const bool sideways=verticalSlot && !vertical && !hero && cjk==0 && visible>=5 && visible<=34;
            const bool caption=!hero && !vertical && !sideways && variation%5==0;
            const int size=hero ? 72+static_cast<int>(variation%4)*10
                : caption ? 23+static_cast<int>(variation%3)*2 : 30+static_cast<int>(variation%5)*5;
            QFont font(family_);font.setPixelSize(size);
            font.setWeight(hero?QFont::ExtraBold:caption?QFont::Medium:QFont::DemiBold);
            QFontMetricsF metrics(font);
            const qreal advance=std::ceil(metrics.height()*1.04);
            qreal contentWidth=0,contentHeight=0;
            QVariantList runs,glyphs;
            int wordIndex=0,wordBegin=0;
            int wordEnd=words.isEmpty()?0:static_cast<int>(words.first().toMap().value("text").toString().size());
            qreal end=index+1<lyrics_.size()?start(lyrics_[index+1].toMap()):start(line)+5000;
            for(const auto& value:words)end=std::max(end,value.toMap().value("endMs").toDouble());
            end=std::max(end,start(line)+1);
            const auto addGlyph=[&](const Grapheme& letter,const QString& display,qreal x,qreal y,qreal width) {
                while(wordIndex+1<words.size() && letter.begin>=wordEnd) {
                    wordBegin=wordEnd;++wordIndex;wordEnd+=static_cast<int>(words[wordIndex].toMap().value("text").toString().size());
                }
                qreal begin=start(line),finish=end;
                if(!words.isEmpty()) {
                    const auto word=words[wordIndex].toMap();
                    const qreal ws=word.value("startMs").toDouble(),we=std::max(ws,word.value("endMs").toDouble());
                    begin=ws+(we-ws)*std::clamp(qreal(letter.begin-wordBegin)/std::max(1,wordEnd-wordBegin),0.,1.);
                    finish=ws+(we-ws)*std::clamp(qreal(letter.end-wordBegin)/std::max(1,wordEnd-wordBegin),0.,1.);
                }
                glyphs.append(QVariantMap{{"text",display},{"sourceText",letter.text},{"x",x},{"y",y},{"width",width},
                    {"height",metrics.height()},{"start",begin},{"end",finish},{"timed",!words.isEmpty()}});
            };
            if(vertical) {
                // Right-to-left columns; keep emoji and combining marks whole.
                const int rows=hero?6:9;
                const int count=static_cast<int>((letters.size()+rows-1)/rows);
                qreal cell=size;
                for(const auto& letter:letters)cell=std::max(cell,metrics.horizontalAdvance(upright(letter.text)));
                const qreal columnGap=size*.3;
                contentWidth=count*cell+(count-1)*columnGap;
                contentHeight=std::min(static_cast<int>(letters.size()),rows)*advance;
                for(int column=0;column<count;++column) {
                    const qreal x=(count-1-column)*(cell+columnGap);
                    QStringList textLines;
                    for(int row=0;row<rows && column*rows+row<letters.size();++row) {
                        const auto& letter=letters[column*rows+row];const auto display=upright(letter.text);
                        textLines.append(display);
                        const qreal width=metrics.horizontalAdvance(display);
                        addGlyph(letter,display,x+(cell-width)*.5,row*advance,width);
                    }
                    runs.append(QVariantMap{{"text",textLines.join('\n')},{"x",x},{"y",0},{"width",cell},
                        {"height",qreal(textLines.size())*advance},{"centered",true}});
                }
            } else {
                // Wrap without squeezing all lines down to the same font size.
                const qreal natural=metrics.horizontalAdvance(text);
                const qreal wrapWidth=sideways?natural+1:hero?std::clamp(natural,520.,pitch*14-gutter)
                    :caption?std::clamp(natural,180.,pitch*8-gutter):std::clamp(natural,160.,pitch*7-gutter);
                QTextLayout layout(text,font);QTextOption option;
                option.setWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);layout.setTextOption(option);
                layout.beginLayout();QList<QTextLine> textLines;
                while(true) {
                    auto tl=layout.createLine();if(!tl.isValid())break;
                    tl.setLineWidth(wrapWidth);tl.setPosition({0,contentHeight});
                    contentWidth=std::max(contentWidth,tl.naturalTextWidth());contentHeight+=advance;textLines.append(tl);
                    runs.append(QVariantMap{{"text",text.mid(tl.textStart(),tl.textLength())},{"x",0},{"y",tl.y()},
                        {"width",tl.naturalTextWidth()+1},{"height",advance},{"centered",false}});
                }
                layout.endLayout();
                for(const auto& letter:letters)for(const auto& tl:textLines) {
                    if(letter.begin<tl.textStart() || letter.begin>=tl.textStart()+tl.textLength())continue;
                    const qreal left=tl.cursorToX(letter.begin),right=tl.cursorToX(letter.end);
                    addGlyph(letter,letter.text,std::min(left,right),tl.y(),std::abs(right-left));break;
                }
            }
            const qreal width=sideways?contentHeight:contentWidth;
            const qreal height=sideways?contentWidth:contentHeight;
            const int span=std::clamp(static_cast<int>(std::ceil((width+gutter)/pitch)),1,columns);
            const int candidates=columns-span+1,tieStart=static_cast<int>(variation%static_cast<uint>(candidates));
            int col=0;qreal y=std::numeric_limits<qreal>::max();
            for(int step=0;step<candidates;++step) {
                const int candidate=(tieStart+step)%candidates;
                const auto top=*std::max_element(bottoms.begin()+candidate,bottoms.begin()+candidate+span);
                if(top<y) {y=top;col=candidate;}
            }
            for(int c=col;c<col+span;++c)bottoms[c]=y+height+gutter;
            blocks_[index]=QVariantMap{{"index",index},{"text",text},{"x",col*pitch},{"y",y},{"width",width},{"height",height},
                {"contentWidth",contentWidth},{"contentHeight",contentHeight},{"rotation",sideways?90:0},
                {"orientation",vertical?"vertical":sideways?"sideways":"horizontal"},{"fontSize",size},{"fontWeight",int(font.weight())},
                {"lineAdvance",advance},{"hero",hero},{"start",start(line)},{"end",end},{"runs",runs},{"glyphs",glyphs}};
        }
        emit layoutChanged();
    }
};
