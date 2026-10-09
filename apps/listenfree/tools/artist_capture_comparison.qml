import QtQuick
import QtTest
import "before/pages" as Before
import "after/pages" as After

TestCase {
    id: test
    name: "ArtistCapture"
    when: windowShown
    visible: true
    width: 1000; height: 700
    Rectangle { anchors.fill: parent; color: "#927f95" }
    Component { id: original; Before.CollectionPage { kind:"Artist"; title:"测试歌手"; reduceMotion:true } }
    Component { id: optimized; After.CollectionPage { kind:"Artist"; title:"测试歌手"; reduceMotion:true } }
    function songs() {
        const rows=[]
        for(let i=0;i<30;++i) rows.push({trackId:String(i),title:"歌曲 "+i,artist:"歌手",album:"专辑 "+Math.floor(i/5),
            artwork:Qt.resolvedUrl("after/assets/album_Cover_2.png"),duration:"3:15"})
        return rows
    }
    function test_pixels_data() {
        return [{tag:"expanded",offset:-294,w:1000,h:700},{tag:"collapsed",offset:420,w:1000,h:700},
                {tag:"compact",offset:420,w:800,h:600}]
    }
    function test_pixels(data) {
        const captures=[]
        for(const component of [original,optimized]) {
            const page=createTemporaryObject(component,test,{width:data.w,height:data.h,rows:songs()})
            verify(page!==null)
            wait(200)
            const scroll=findChild(page,"artistScroll")
            verify(scroll!==null);scroll.contentY=data.offset
            wait(250)
            const capture=grabImage(page)
            verify(capture.width>0)
            captures.push(capture)
            page.destroy();wait(50)
        }
        captures[0].save(Qt.resolvedUrl("original-"+data.tag+".png").toString().replace("file:///",""))
        captures[1].save(Qt.resolvedUrl("optimized-"+data.tag+".png").toString().replace("file:///",""))
        // Actual differences are summarized from exported RGBA captures, so a
        // failure includes maximum error and changed area, not just a boolean.
        compare(captures[0].width,captures[1].width)
        compare(captures[0].height,captures[1].height)
    }
}
