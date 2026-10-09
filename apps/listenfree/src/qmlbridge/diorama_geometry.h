#pragma once
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>
#include <QQuaternion>
#include <QVector3D>
#include <QVector4D>
#include <QColor>
#include <QSizeF>
#include <QVector>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>

// Native narrow adaptation of Folia dc5a07e (AGPL-3.0): cameraPath's
// formations and dioramaParticleSurfaces' welded, count-independent lattices.
// See docs/research/diorama-camera-stage-2026-09-10.md.
namespace diorama {
constexpr float pi=3.14159265358979323846f;
constexpr int pointsPerShape=512;
struct Shape {int kind=0;QVector3D center;qreal scale=1,stretch=1,phase=0;int color=0;};
inline QVector<Shape> formation(int shot,quint32 seed,qreal halfTextWidth){
    QVector<Shape> shapes;shapes.reserve(8);
    const auto rnd=[&](int n){quint32 x=seed+quint32(n)*0x9e3779b9u;x^=x>>16;x*=0x7feb352du;x^=x>>15;return qreal(x%10000)/10000;};
    const auto add=[&](int kind,qreal x,qreal y,qreal z,qreal scale,qreal stretch=1){
        shapes.append({kind,QVector3D(x,y,z),scale,stretch,rnd(shapes.size()+41)*2*pi,int(shapes.size())%2});
    };
    const auto pair=[&](int kind,qreal x,qreal y,qreal z,qreal scale,qreal stretch=1){add(kind,-x,y,z,scale,stretch);add(kind,x,y,z,scale,stretch);};
    switch(shot%13){
    case 0:pair(0,4.3,-.6,.7,.78,3.1);pair(0,5.9,.6,5.5,1.,3.4);break;
    case 1:pair(1,5.8,1.25,7.2,1.45);pair(0,4.4,-1.4,2.2,.8,1.5);pair(2,5.55,.8,4.3,.9);break;
    case 2:for(int j=0;j<6;++j){const qreal a=j*pi/3+rnd(2)*.6;add(j==0?3:1,std::cos(a)*4.6,std::sin(a)*3.7,.8+rnd(j+10)*1.4,.7+rnd(j+20)*.25);}break;
    case 3:for(int j=0;j<3;++j)pair(0,4.3,-.4,.5+j*2.4,.75,2.8);break;
    case 4:for(int j=0;j<5;++j){const qreal a=pi*(.15+.7*j/4);add(0,std::cos(a)*4.1,-std::sin(a)*3.2-1.,.8+rnd(j+30),.72,1.6);}break;
    case 6:pair(0,4.5,1.5,1.,.72,1.8);pair(0,4.5,-.6,2.2,.64,1.8);pair(1,4.5,-2.7,3.4,.8);break;
    case 7:for(int j=0;j<7;++j){const qreal a=j/6.*pi*2.2;add(1,std::cos(a)*4.5,2.2-j/6.*5.2,.5+j/6.*2.2,.6+rnd(j+20)*.25);}break;
    case 8:for(int j=0;j<4;++j)add(0,-3.9+j*2.6,-3.4-rnd(j),.5+rnd(j+10),.58,2.8);break;
    case 9:for(int j=0;j<3;++j)pair(0,4.5,-.45+j*.45,1+j*2.1,.66,2.5);break;
    case 10:for(int j=0;j<3;++j)pair(1,4.2+j*.85,1.2-j*1.35,1.2+j*1.55,.7+rnd(j)*.2);break;
    case 11:for(int j=0;j<3;++j)pair(0,4.4,1.5-j*1.7,1+j*1.7,.7,2.);break;
    case 12:for(int j=0;j<5;++j){const qreal a=(-.5+j/4.)*pi*.85;add(0,std::sin(a)*5.4,-2.2,2.+std::cos(a)*2.2,.75,2.5);}break;
    default:pair(3,5.6,-1.55,7.5,1.3);pair(1,4.45,1.1,2.4,.85);break;
    }
    const auto radius=[](const Shape& s){return s.scale*std::max(s.kind==0?.55:s.kind==1?.75:s.kind==2?.9:.82,s.stretch*.55)*1.18;};
    const auto clear=[&]{for(int i=0;i<shapes.size();++i){auto& s=shapes[i];const auto r=radius(s);
        const qreal rail=std::hypot(s.center.x(),s.center.y());
        if(rail<2.8+r&&rail>.001)s.center*=float((2.8+r)/rail);
        if(std::abs(s.center.y())-r<1.15&&std::abs(s.center.x())-r<halfTextWidth+.45)
            s.center.setX((s.center.x()<0?-1.f:1.f)*float(halfTextWidth+.6+r));
        s.center.setZ(std::max(.5f,s.center.z()));}};
    clear();
    for(int pass=0;pass<6;++pass)for(int a=0;a<shapes.size();++a)for(int b=a+1;b<shapes.size();++b){
        auto delta=shapes[b].center-shapes[a].center;const qreal distance=delta.length(),minimum=(radius(shapes[a])+radius(shapes[b]))*1.15;
        if(distance>=minimum)continue;if(distance<.001)delta=QVector3D(1,.5,.25);
        const auto push=delta.normalized()*float((minimum-distance)*.5);shapes[a].center-=push;shapes[b].center+=push;
    }
    clear();return shapes;
}
inline QVector<QVector3D> surface(int kind,qreal stretch){
    QVector<QVector3D> result;result.reserve(pointsPerShape);
    if(kind==0){
        int across=2,tall=2;
        for(int n=3;n<32;++n){const int y=std::max(2,qRound(1+(n-1)*stretch));
            if(2*(n*y+y*n+n*n)-4*(n+y+n)+8>pointsPerShape)break;across=n;tall=y;}
        for(int y=0;y<tall;++y)for(int z=0;z<across;++z)for(int x=0;x<across;++x){
            if(x>0&&x<across-1&&y>0&&y<tall-1&&z>0&&z<across-1)continue;
            result.append(QVector3D((qreal(x)/(across-1)-.5)*1.1,(qreal(y)/(tall-1)-.5)*1.1*stretch,(qreal(z)/(across-1)-.5)*1.1));}
    }else if(kind==2){
        const std::array<QVector3D,4> v={QVector3D(0,.86,0),QVector3D(-.81,-.5,.47),QVector3D(.81,-.5,.47),QVector3D(0,-.5,-.94)};
        const int faces[4][3]={{0,1,2},{0,2,3},{0,3,1},{1,3,2}};
        for(const auto& face:faces)for(int i=0;i<=14;++i)for(int j=0;j<=14-i;++j)
            result.append(v[face[0]]*(i/14.f)+v[face[1]]*(j/14.f)+v[face[2]]*(1-(i+j)/14.f));
    }else if(kind==3){
        for(int ring=0;ring<48;++ring)for(int tube=0;tube<10;++tube){const qreal a=ring*pi/24,b=tube*pi/5;
            result.append(QVector3D((.68+.12*std::cos(b))*std::cos(a),(.68+.12*std::cos(b))*std::sin(a),.12*std::sin(b)));}
    }else{
        // Latitude grid, welded at the poles and seam, like the source's
        // regular surfaces; coherent neighbouring samples survive ripples.
        result.append(QVector3D(0,.75,0));result.append(QVector3D(0,-.75,0));
        for(int row=1;row<16;++row)for(int col=0;col<32;++col){const qreal a=row*pi/16,b=col*pi/16;
            result.append(QVector3D(.75*std::sin(a)*std::cos(b),.75*std::cos(a),.75*std::sin(a)*std::sin(b)));}
    }
    return result;
}
struct Vertex {float bounds[2],offset[3],anchor[3],style[2];};
struct Particle {QVector3D offset,anchor;qreal phase=0;int color=0;};
class Material;
class Shader final:public QSGMaterialShader {
public:
    Shader(){setShaderFileName(VertexStage,":/shaders/diorama-particles.vert.qsb");setShaderFileName(FragmentStage,":/shaders/diorama-particles.frag.qsb");}
    bool updateUniformData(RenderState& state,QSGMaterial* material,QSGMaterial*)override;
};
class Material final:public QSGMaterial {
public:
    Material(){setFlag(Blending);setFlag(RequiresFullMatrix);setFlag(NoBatching);}
    QSGMaterialType* type()const override{static QSGMaterialType type;return &type;}
    QSGMaterialShader* createShader(QSGRendererInterface::RenderMode)const override{return new Shader;}
    QMatrix4x4 view;QVector4D viewport,controls,accent,focusRect;
};
inline bool Shader::updateUniformData(RenderState& state,QSGMaterial* material,QSGMaterial*){
    const auto& m=*static_cast<Material*>(material);auto* data=state.uniformData();
    const auto matrix=state.combinedMatrix();std::memcpy(data->data(),matrix.constData(),64);
    std::memcpy(data->data()+64,m.view.constData(),64);
    std::memcpy(data->data()+128,&m.viewport,16);
    auto controls=m.controls;controls.setW(state.opacity());std::memcpy(data->data()+144,&controls,16);
    std::memcpy(data->data()+160,&m.accent,16);
    std::memcpy(data->data()+176,&m.focusRect,16);return true;
}
class Node final:public QSGGeometryNode {
public:
    const void* owner=nullptr;unsigned revision=0;int first=-1,last=-1;QSizeF size;
    Node(){
        static const QSGGeometry::Attribute attributes[]={
            QSGGeometry::Attribute::create(0,2,QSGGeometry::FloatType,true),
            QSGGeometry::Attribute::create(1,3,QSGGeometry::FloatType),
            QSGGeometry::Attribute::create(2,3,QSGGeometry::FloatType),
            QSGGeometry::Attribute::create(3,2,QSGGeometry::FloatType)};
        static const QSGGeometry::AttributeSet set={4,sizeof(Vertex),attributes};
        auto* geometry=new QSGGeometry(set,0,0,QSGGeometry::UnsignedIntType);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);geometry->setVertexDataPattern(QSGGeometry::StaticPattern);geometry->setIndexDataPattern(QSGGeometry::StaticPattern);
        setGeometry(geometry);setFlag(OwnsGeometry);setMaterial(new Material);setFlag(OwnsMaterial);
    }
    void upload(const QVector<Particle>& points){
        auto* geo=geometry();geo->allocate(points.size()*4,points.size()*6);
        auto* v=static_cast<Vertex*>(geo->vertexData());auto* indices=geo->indexDataAsUInt();
        for(int i=0;i<points.size();++i){const auto& p=points[i];
            for(int j=0;j<4;++j)v[i*4+j]={{float((j%2)*size.width()),float((j/2)*size.height())},
                {p.offset.x(),p.offset.y(),p.offset.z()},{p.anchor.x(),p.anchor.y(),p.anchor.z()},{float(p.phase),float(p.color)}};
            const unsigned order[6]={0,1,2,1,3,2};for(int j=0;j<6;++j)indices[i*6+j]=i*4+order[j];
        }
        markDirty(DirtyGeometry);
    }
};
}
