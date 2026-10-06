import QtQuick
import QtQuick3D
import Kos.Spatial3D 1.0

Item {
    id: root
    property url wallpaperPath
    property url depthPath
    property url backgroundPath
    property url mattePath
    property size textureSize: Qt.size(Math.max(1, width), Math.max(1, height))
    property real pointerX: 0
    property real pointerY: 0
    property real outputAspect: width > 0 && height > 0 ? width / height : 16 / 9
    readonly property real imageZoom: 1.16
    readonly property real focusZ: -depthGeometry.focusDistance
    readonly property real foregroundTravel: 0.005
    readonly property vector2d boundedPointer: Qt.vector2d(
        Math.max(-1, Math.min(1, root.pointerX)),
        Math.max(-1, Math.min(1, root.pointerY)))
    readonly property real focusHalfHeight: depthGeometry.focusDistance
        * Math.tan(Math.PI * 42 / 360)
    readonly property bool ready: depthGeometry.valid
        && foregroundGeometry.valid
        && sourceInfo.status === Image.Ready
        && backgroundInfo.status === Image.Ready
        && matteInfo.status === Image.Ready
    readonly property real sourceAspect: sourceInfo.implicitHeight > 0
        ? sourceInfo.implicitWidth / sourceInfo.implicitHeight : outputAspect
    readonly property vector2d cropScale: Qt.vector2d(
        Math.min(1, outputAspect / sourceAspect),
        Math.min(1, sourceAspect / outputAspect))

    Image {
        id: sourceInfo
        visible: false
        source: root.wallpaperPath
        autoTransform: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: root.textureSize
        asynchronous: true
    }
    Image {
        id: backgroundInfo
        visible: false
        source: root.backgroundPath
        sourceSize: root.textureSize
        asynchronous: true
    }
    Image {
        id: matteInfo
        visible: false
        source: root.mattePath
        sourceSize: root.textureSize
        asynchronous: true
    }

    View3D {
        id: view
        anchors.fill: parent
        visible: root.ready
        camera: camera
        renderMode: View3D.Offscreen
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            id: camera
            fieldOfView: 42
            fieldOfViewOrientation: PerspectiveCamera.Vertical
            clipNear: 0.01
            clipFar: 100
            position: Qt.vector3d(0, 0, 0)
            Component.onCompleted: lookAt(Qt.vector3d(0, 0, root.focusZ))
        }

        Model {
            visible: root.backgroundPath.toString().length > 0
            position: Qt.vector3d(0, 0, -depthGeometry.backgroundDistance)
            source: "#Rectangle"
            scale: Qt.vector3d(
                root.imageZoom * 2 * depthGeometry.backgroundDistance
                    * Math.tan(Math.PI * 42 / 360) * root.outputAspect / 100,
                root.imageZoom * 2 * depthGeometry.backgroundDistance
                    * Math.tan(Math.PI * 42 / 360) / 100, 1)
            materials: DefaultMaterial {
                lighting: DefaultMaterial.NoLighting
                cullMode: Material.NoCulling
                diffuseMap: Texture {
                    source: root.backgroundPath
                    minFilter: Texture.Linear
                    magFilter: Texture.Linear
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                }
            }
        }

        Model {
            geometry: DepthMeshGeometry {
                id: depthGeometry
                depthPath: root.depthPath
                mattePath: root.mattePath
                imageZoom: root.imageZoom
                outputAspect: root.outputAspect
                sourceAspect: root.sourceAspect
            }
            materials: DefaultMaterial {
                lighting: DefaultMaterial.NoLighting
                cullMode: Material.NoCulling
                diffuseMap: Texture {
                    source: root.backgroundPath
                    minFilter: Texture.Linear
                    magFilter: Texture.Linear
                    tilingModeHorizontal: Texture.ClampToEdge
                    tilingModeVertical: Texture.ClampToEdge
                }
            }
        }

        // The subject shares the background's camera, with its own depth
        // relief. Sample the original soft matte at fragment resolution so
        // fingers and hair are not clipped to a coarse triangle silhouette.
        Model {
            // Orbiting around the focus plane leaves the subject almost
            // stationary. Add a small near-field translation, opposite the
            // far field, without rebuilding the mesh or separating its matte.
            position: Qt.vector3d(
                -root.boundedPointer.x * root.focusHalfHeight * root.outputAspect
                    * root.foregroundTravel * 2,
                root.boundedPointer.y * root.focusHalfHeight
                    * root.foregroundTravel * 2, 0)
            geometry: DepthMeshGeometry {
                id: foregroundGeometry
                foreground: true
                depthPath: root.depthPath
                mattePath: root.mattePath
                imageZoom: root.imageZoom
                outputAspect: root.outputAspect
                sourceAspect: root.sourceAspect
            }
            materials: CustomMaterial {
                shadingMode: CustomMaterial.Unshaded
                cullMode: Material.NoCulling
                depthDrawMode: Material.NeverDepthDraw
                sourceBlend: CustomMaterial.One
                destinationBlend: CustomMaterial.OneMinusSrcAlpha
                vertexShader: Qt.resolvedUrl("shaders/spatial_subject.vert")
                fragmentShader: Qt.resolvedUrl("shaders/spatial_subject.frag")
                property TextureInput sourceTexture: TextureInput {
                    enabled: true
                    texture: Texture {
                        source: root.wallpaperPath
                        minFilter: Texture.Linear
                        magFilter: Texture.Linear
                        tilingModeHorizontal: Texture.ClampToEdge
                        tilingModeVertical: Texture.ClampToEdge
                    }
                }
                property TextureInput matteTexture: TextureInput {
                    enabled: true
                    texture: Texture {
                        source: root.mattePath
                        minFilter: Texture.Linear
                        magFilter: Texture.Linear
                        tilingModeHorizontal: Texture.ClampToEdge
                        tilingModeVertical: Texture.ClampToEdge
                    }
                }
                property TextureInput backgroundTexture: TextureInput {
                    enabled: true
                    texture: Texture {
                        source: root.backgroundPath
                        minFilter: Texture.Linear
                        magFilter: Texture.Linear
                        tilingModeHorizontal: Texture.ClampToEdge
                        tilingModeVertical: Texture.ClampToEdge
                    }
                }
            }
        }
    }

    function updateCamera() {
        const tiltX = root.boundedPointer.x
        const tiltY = root.boundedPointer.y
        const yaw = tiltX * Math.PI * 4 / 180
        const pitch = -tiltY * Math.PI * 3 / 180
        const radius = depthGeometry.focusDistance
        camera.position = Qt.vector3d(Math.sin(yaw) * Math.cos(pitch) * radius,
            Math.sin(pitch) * radius,
            root.focusZ + Math.cos(yaw) * Math.cos(pitch) * radius)
        camera.lookAt(Qt.vector3d(0, 0, root.focusZ))
    }
    onBoundedPointerChanged: updateCamera()
    onOutputAspectChanged: updateCamera()
    Connections {
        target: depthGeometry
        function onFocusDistanceChanged() { root.updateCamera() }
    }
    Component.onCompleted: updateCamera()
}
