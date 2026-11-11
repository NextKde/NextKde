import QtQuick
Icon {
    property real level: 0
    property bool muted: false
    name: muted ? "speaker_slash_fill" : level > 0.66 ? "speaker_3_fill"
        : level > 0.33 ? "speaker_2_fill" : level > 0 ? "speaker_1_fill" : "speaker_fill"
}
