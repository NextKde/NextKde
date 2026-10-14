import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.notifications
Scope {
    id: test
    property var identities: []
    property var frameTimes: []
    property bool sampling: false
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) { const found=find(child,name); if(found)return found }
        return null
    }
    PanelWindow {
        id: background
        WlrLayershell.layer: WlrLayer.Background
        anchors { left:true; right:true; top:true; bottom:true }
        color: "#557399"
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {position:0;color:"#4c609d"}
                GradientStop {position:0.5;color:"#72acba"}
                GradientStop {position:1;color:"#d5b5ac"}
            }
        }
        Rectangle { x:60;y:50;width:380;height:500;radius:190;color:"#a5c6b5";opacity:0.5;rotation:35 }
        Rectangle { x:950;y:470;width:420;height:310;radius:155;color:"#477bb6";opacity:0.7;rotation:25 }
        Rectangle { x:280;y:340;width:300;height:300;radius:150;color:"#4e72a9";opacity:0.45 }
    }
    PanelWindow {
        id: anchorHost
        WlrLayershell.layer: WlrLayer.Top
        anchors {top:true;right:true}
        implicitWidth:336;implicitHeight:32
        color:"transparent"
        Rectangle { id:anchor; x:260;y:0;width:30;height:28;radius:14;color:"#ffffff";opacity:0.4 }
        ControlCenterPanel { id:center; anchorItem:anchor }
    }
    IpcHandler {
        target:"preview"
        function theme(mode:string):void { AppearanceConfigService.glassFollowsAppearanceMode=true; AppearanceConfigService.themeMode=mode }
        function sample():void {
            const list=test.find(center.contentItem,"notification-history-list")
            test.identities=[0,1,2].map(i=>list.itemAtIndex(i).cardItem)
            test.frameTimes=[]; test.sampling=true
        }
        function expand(value:bool):void { test.find(center.contentItem,"notification-history-pane").requestExpanded(value) }
        function stats():string {
            const pane=test.find(center.contentItem,"notification-history-pane")
            const list=test.find(center.contentItem,"notification-history-list")
            return JSON.stringify({open:center.isOpen,width:center.width,height:center.height,
                scale:center.fitScale, controlsWidth:center.controlsWidth, natural:center.naturalContentHeight, paneHeight:pane.height,
                preview:pane.displayedMessageCount, painted:pane.paintedCards.length,
                older:pane.expanded, listHeight:list.height, contentHeight:list.contentHeight,
                capture:pane.captureAnchor!==null,
                fixedCapture:list.itemAtIndex(0)?.cardItem?.fixedCaptureSupported ?? false,
                keys:[0,1,2].map(i=>list.itemAtIndex(i)?.cardItem?.historyKey ?? -1),
                retained:test.identities.length===3 && test.identities.every((card,i)=>list.itemAtIndex(i)?.cardItem===card),
                frames:test.frameTimes})
        }
        function outerScroll():void {
            const viewport=test.find(center.contentItem,"control-center-viewport")
            viewport.contentY=Math.max(0,viewport.contentHeight-viewport.height)
        }
        function scroll():void { test.find(center.contentItem,"notification-history-list").flick(0,-1200) }
        function home():void { test.find(center.contentItem,"notification-history-list").positionViewAtBeginning() }
    }
    FrameAnimation {
        running:test.sampling && center.isOpen
        onTriggered: {
            const pane=test.find(center.contentItem,"notification-history-pane")
            const list=test.find(center.contentItem,"notification-history-list")
            if (pane && list && (pane.revealProgress>0.001 && pane.revealProgress<0.999 || list.moving))
                test.frameTimes.push(frameTime*1000)
        }
    }
    Component.onCompleted: {
        const data = [
            ["日历", "会议将在 15 分钟后开始", "设计评审 · 下午 2:00\n会议室 3 / 在线会议", "x-office-calendar"],
            ["邮件", "王悦", "新版界面稿已更新，欢迎查看今天的修改。", "mail-message-new"],
            ["提醒事项", "今天的计划", "完成通知中心的视觉细节", "task-complete"]
        ]
        for(let i=7;i>=0;--i) {
            const row=data[i%3]
            NotificationHistoryService.push({notifId:i+100,appName:row[0],desktopEntry:"org.test."+(i%3),
                appIcon:row[3],summary:row[1],body:row[2],timestamp:Date.now()-i*60000,urgency:1})
        }
    }
    Timer {running:true;interval:1600;onTriggered:center.toggle(anchor)}
}
