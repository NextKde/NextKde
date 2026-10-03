import QtQuick

Item {
    id: root
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    property var widgetRects: []
    signal frameReady()
    function hash(n) { const v=Math.sin(n*127.1)*43758.5453; return v-Math.floor(v) }
    // z=0 is distant scenery, z=0.5 the widget plane, z=1 the viewer.
    function flightAngle(i) { return phase*(0.38+hash(i+9)*0.16)+i*13.71+4 }
    function depth(i) { return 0.5+0.5*Math.sin(flightAngle(i)+0.8) }
    function frontWeight(i) {
        const t=Math.max(0,Math.min(1,(depth(i)-0.44)/0.12))
        return t*t*(3-2*t)
    }
    function illumination(i) { return brightness(i)*frontWeight(i)*(0.45+0.55*Math.exp(-Math.pow((depth(i)-0.5)*4,2))) }
    function position(i) {
        const seed=i*13.71+4, aspect=width/Math.max(1,height)
        let x=hash(seed+2)+Math.sin(phase*0.28+seed)*0.075
        let y=0.18+hash(seed+3)*0.70+Math.sin(phase*0.41+seed)*0.045
        if(i<24 && widgetRects.length) {
            const r=widgetRects[i%Math.min(8,widgetRects.length)]
            const angle=flightAngle(i), z=depth(i)
            const perspective=0.65+z*0.7
            const cardX=(r.x+r.width*(0.5+Math.sin(angle)*0.60*perspective))/Math.max(1,width)
            const cardY=(r.y+r.height*(0.5+Math.cos(angle)*0.42*perspective))/Math.max(1,height)
            // As it recedes, the same insect leaves the widget orbit for the scenery.
            const orbitWeight=Math.min(1,z/0.3)
            x+=(cardX-x)*orbitWeight; y+=(cardY-y)*orbitWeight
        }
        if(pointer.z>0) {
            const dx=(x-pointer.x)*aspect,dy=y-pointer.y
            const gather=Math.exp(-(dx*dx+dy*dy)*8)*(i<16?0.85:0.25)
            const angle=phase*(0.6+hash(seed)*0.4)+seed, radius=0.035+hash(seed+8)*0.055
            x+=(pointer.x+Math.cos(angle)*radius/aspect-x)*gather
            y+=(pointer.y+Math.sin(angle)*radius-y)*gather
        }
        const age=phase-clickPulse.z
        if(age>=0 && age<8) {
            const dx=(x-clickPulse.x)*aspect,dy=y-clickPulse.y,d=Math.sqrt(dx*dx+dy*dy)
            const kick=Math.exp(-d*d*18-age*0.85)*0.15/Math.max(d,0.0001)
            x+=dx/aspect*kick; y+=dy*kick
        }
        return Qt.point(x*width,y*height)
    }
    function brightness(i) { return 0.45+0.55*Math.pow(0.5+0.5*Math.sin(phase*1.3+i*13.71+4),3) }
    Image {
        anchors.fill: parent
        visible: !root.foreground
        source: root.foreground ? "" : "assets/forest-cinematic.png"
        sourceSize: Qt.size(Math.max(1, Math.min(2048, Math.ceil(root.width))),
            Math.max(1, Math.min(2048, Math.ceil(root.height))))
        fillMode: Image.PreserveAspectCrop
        smooth: true
        onStatusChanged: if(status===Image.Ready) Qt.callLater(root.frameReady)
    }
    // Each glow covers a small quad; flight is calculated once per particle.
    Repeater {
        model: root.economical ? 32 : 72
        delegate: Image {
            required property int index
            readonly property real depth: root.depth(index)
            readonly property real pass: root.foreground ? root.frontWeight(index) : 1-root.frontWeight(index)
            readonly property point location: root.position(index)
            width: (28+depth*64)*(0.75+root.hash(index+5)*0.5)
            height: width
            x: location.x-width/2; y: location.y-height/2
            visible: pass>0.001
            opacity: root.brightness(index)*(0.45+depth*0.5)*pass
            source: index%3===0 ? "assets/firefly-green.svg" : "assets/firefly-gold.svg"
            sourceSize: Qt.size(96, 96)
            smooth: true
        }
    }
    Repeater {
        model: root.foreground ? Math.min(8,root.widgetRects.length) : 0
        delegate: ShaderEffect {
            required property int index
            readonly property var rect: root.widgetRects[index]
            readonly property int stride: Math.min(8,root.widgetRects.length)
            x: rect.x-8; y: rect.y-8; width: rect.width+16; height: rect.height+16
            property vector2d extent: Qt.vector2d(width,height)
            property vector2d light0: {const p=root.position(index);return Qt.vector2d(p.x-x,p.y-y)}
            property vector2d light1: {const p=root.position(index+stride);return Qt.vector2d(p.x-x,p.y-y)}
            property vector2d light2: {const p=root.position(index+stride*2);return Qt.vector2d(p.x-x,p.y-y)}
            property vector3d intensity: Qt.vector3d(root.illumination(index),root.illumination(index+stride),root.illumination(index+stride*2))
            fragmentShader: "shaders/forest_card_light.frag.qsb"
        }
    }
    Component.onCompleted: Qt.callLater(root.frameReady)
}
