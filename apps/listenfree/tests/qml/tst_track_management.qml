import QtQuick
import QtTest
import "Components"

TestCase {
    id: test
    name: "TrackManagement"
    visible: true
    when: windowShown
    width: 800; height: 500
    QtObject {
        id: player
        property var currentTrack: ({trackUid:"tx42"})
        property string state: "Stopped"
        function isCurrentTrack(track) { return track.trackUid === currentTrack.trackUid }
        function requestTrackArtwork(track) {}
        signal trackArtworkResolved(string source, string rid, string artwork)
    }
    Component { id: rowFactory; SongRow { width: 780; playerController: player; favorites: null } }
    function test_locations_and_loading() {
        const providers=["local","kw","kg","tx","wy","mg","bili"]
        const labels=["本地音乐","酷我","酷狗","QQ 音乐","网易云","咪咕","哔哩哔哩"]
        const rows=[]
        for(let i=0;i<providers.length;++i) {
            const row=createTemporaryObject(rowFactory,test,{y:i*64,track:{source:providers[i],title:"同名歌曲",artist:"测试歌手",trackUid:providers[i]+"42"}})
            verify(row);compare(row.originLabel,labels[i]);rows.push(row)
        }
        player.state="Loading"
        tryCompare(rows[3],"waiting",true)
        for(let i=0;i<rows.length;++i) {
            const indicator=findChild(rows[i],"trackWaitingIndicator")
            verify(indicator);compare(indicator.visible,i===3)
        }
        player.state="Buffering";compare(rows[3].waiting,true)
        player.state="Playing";tryCompare(rows[3],"waiting",false)
        player.currentTrack={trackUid:"wy42"};player.state="Loading"
        tryCompare(rows[4],"waiting",true);compare(rows[3].waiting,false)
        player.state="Stopped";tryCompare(rows[4],"waiting",false)
        rows[3].track={source:"tx",title:"Script song",originKind:"lx",originSourceName:"Fixture",trackUid:"script42"}
        compare(rows[3].originLabel,"QQ 音乐 · Fixture")
    }
    function test_long_title_leaves_room_for_indicator() {
        const row=createTemporaryObject(rowFactory,test,{width:360,track:{source:"tx",title:"A long song title that must be elided without hiding the waiting indicator",trackUid:"tx42"}})
        verify(row);player.currentTrack={trackUid:"tx42"};player.state="Loading"
        tryCompare(row,"waiting",true)
        const indicator=findChild(row,"trackWaitingIndicator")
        verify(indicator.x+indicator.width<=indicator.parent.width)
        player.state="Stopped"
    }
}
