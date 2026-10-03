import QtQuick

Item {
    id: root
    property string themeId: "starfield"
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property int particleCount: 80
    property var obstacles: []
    function obstacle(index) { return obstacles[index] || Qt.vector4d(-10,-10,0,0) }
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    readonly property int count: Math.max(24, Math.min(economical ? 72 : 160, particleCount))
    property real committedPhase: 0
    property real submittedPhase: 0
    property real stepDelta: 0
    property bool initializing: true
    property bool busy: false
    property bool ready: false
    property bool resetPending: false
    function submit() {
        if (busy) return
        submittedPhase = phase
        stepDelta = initializing ? 0 : Math.max(0, Math.min(0.2, phase - committedPhase))
        busy = true
        stateTexture.scheduleUpdate()
    }
    function reset() {
        if (busy) { resetPending = true; return }
        resetPending = false
        initializing = true
        ready = false
        if (!busy) Qt.callLater(submit)
    }
    onPhaseChanged: if (!initializing) submit()
    onCountChanged: reset()
    onThemeIdChanged: reset()
    Component.onCompleted: Qt.callLater(submit)

    ShaderEffect {
        id: simulation
        width: root.count; height: 16
        visible: false
        blending: false
        property var previous: stateTexture
        property real time: root.submittedPhase
        property real delta: root.stepDelta
        property real initialize: root.initializing ? 1 : 0
        property real count: root.count
        property real theme: root.themeId === "blackhole" ? 1 : root.themeId === "weather" ? 2 : 0
        property vector4d pointer: root.pointer
        property vector4d clickPulse: root.clickPulse
        property vector4d obstacle0: root.obstacle(0)
        property vector4d obstacle1: root.obstacle(1)
        property vector4d obstacle2: root.obstacle(2)
        property vector4d obstacle3: root.obstacle(3)
        property vector4d obstacle4: root.obstacle(4)
        property vector4d obstacle5: root.obstacle(5)
        property vector4d obstacle6: root.obstacle(6)
        property vector4d obstacle7: root.obstacle(7)

        fragmentShader: "shaders/flow_simulate.frag.qsb"
    }
    ShaderEffectSource {
        id: stateTexture
        sourceItem: simulation
        textureSize: Qt.size(root.count, 16)
        format: ShaderEffectSource.RGBA32F
        live: false
        recursive: true
        smooth: false
        visible: false
        onScheduledUpdateCompleted: {
            root.committedPhase = root.submittedPhase
            root.initializing = false
            root.busy = false
            root.ready = true
            if (root.resetPending) Qt.callLater(root.reset)
            else if (root.phase !== root.committedPhase) Qt.callLater(root.submit)
        }
    }
    Repeater {
        model: root.count
        ShaderEffect {
            required property int index
            anchors.fill: parent
            // Sampling is required to schedule the first recursive texture frame.
            // The shader itself masks uninitialized particles with zero lifetime.
            visible: true
            property var state: stateTexture
            property vector2d viewport: Qt.vector2d(root.width, root.height)
            property real particleIndex: index
            property real count: root.count
            property real foreground: root.foreground ? 1 : 0
            property real theme: root.themeId === "blackhole" ? 1 : root.themeId === "weather" ? 2 : 0
            vertexShader: "shaders/flow_particle.vert.qsb"
            fragmentShader: "shaders/flow_particle.frag.qsb"
        }
    }
}
