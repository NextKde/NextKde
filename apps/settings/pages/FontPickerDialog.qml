import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Demo as Demo
import "../../../shared/qml/i18n"
import "../components" as Controls

Demo.LiquidDialog {
    id: picker
    required property var colors
    property var backend: null
    property string category: "font"
    property font originalFont: Qt.font({pointSize: 10})
    property font selectedFont: originalFont
    property string selectedFamily: ""
    property string selectedStyle: ""
    property var families: []
    readonly property var styles: backend && selectedFamily ? backend.fontStyles(selectedFamily) : []
    readonly property var filteredFamilies: families.filter(name =>
        name.toLocaleLowerCase().includes(search.text.trim().toLocaleLowerCase()))
    property bool applyFamily: true
    property bool applyStyle: true
    property bool applySize: true
    readonly property bool validSelection: families.indexOf(selectedFamily) >= 0
        && styles.indexOf(selectedStyle) >= 0 && sizeInput.acceptableInput
        && (category !== "all" || applyFamily || applyStyle || applySize)

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, parent ? parent.width - 24 : 560)
    height: Math.min(implicitHeight, parent ? parent.height - 24 : implicitHeight)
    title: I18n.tr(category === "all" ? "Adjust all fonts" : "Choose a font")
    standardButtons: Dialog.NoButton

    function updateSelection() {
        if (backend && selectedFamily && selectedStyle && sizeInput.acceptableInput)
            selectedFont = backend.selectionFont(originalFont, selectedFamily,
                selectedStyle, Number(sizeInput.text));
    }
    function selectFamily(name) {
        selectedFamily = name;
        if (styles.indexOf(selectedStyle) < 0)
            selectedStyle = styles.length > 0 ? styles[0] : "";
        updateSelection();
    }
    function choose(role, font) {
        category = role;
        originalFont = font;
        families = backend ? backend.fontFamilies(role === "fixed") : [];
        search.text = "";
        sizeInput.text = String(font.pointSize > 0 ? font.pointSize : 10);
        selectedFamily = font.family;
        selectedStyle = backend ? backend.fontStyleName(font) : font.styleName;
        if (styles.indexOf(selectedStyle) < 0)
            selectedStyle = styles.length > 0 ? styles[0] : "";
        selectedFont = font;
        applyFamily = true;
        applyStyle = true;
        applySize = true;
        open();
        Qt.callLater(function() {
            familyList.currentIndex = filteredFamilies.indexOf(selectedFamily);
            familyList.positionViewAtIndex(familyList.currentIndex, ListView.Center);
            search.forceActiveFocus();
        });
    }

    contentItem: ScrollView {
        implicitHeight: form.implicitHeight
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            id: form
            width: parent.width
            spacing: 12
            Demo.SettingsTextField {
                id: search
                objectName: "font-family-search"
                Layout.fillWidth: true
                implicitHeight: 32
                filled: true
                placeholderText: I18n.tr("Search fonts")
                Accessible.name: placeholderText
                Keys.onDownPressed: {
                    familyList.forceActiveFocus();
                    familyList.currentIndex = Math.max(0, picker.filteredFamilies.indexOf(picker.selectedFamily));
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 172
                radius: 10
                color: picker.colors.card
                ListView {
                    id: familyList
                    objectName: "font-family-list"
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: picker.filteredFamilies
                    keyNavigationEnabled: false
                    ScrollBar.vertical: ScrollBar { }
                    Keys.onDownPressed: {
                        currentIndex = Math.min(count - 1, currentIndex + 1);
                        if (currentIndex >= 0) picker.selectFamily(picker.filteredFamilies[currentIndex]);
                    }
                    Keys.onUpPressed: {
                        currentIndex = Math.max(0, currentIndex - 1);
                        if (count > 0) picker.selectFamily(picker.filteredFamilies[currentIndex]);
                    }
                    delegate: ItemDelegate {
                        id: familyRow
                        required property string modelData
                        required property int index
                        width: ListView.view.width - 12
                        height: 30
                        text: modelData
                        highlighted: picker.selectedFamily === modelData
                        onClicked: {
                            familyList.currentIndex = index;
                            picker.selectFamily(modelData);
                        }
                        contentItem: Text {
                            text: familyRow.modelData
                            font.family: familyRow.modelData
                            font.pixelSize: 13
                            color: familyRow.highlighted ? "white" : picker.colors.primaryText
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: 6
                            color: familyRow.highlighted ? picker.colors.accent
                                : familyRow.hovered ? Qt.rgba(0.5, 0.5, 0.5, 0.12) : "transparent"
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: familyList.count === 0
                        text: I18n.tr("No matching fonts")
                        color: picker.colors.secondaryText
                        font.pixelSize: 12
                    }
                }
            }
            Demo.SettingsGroup {
                Layout.fillWidth: true
                backgroundColor: picker.colors.card
                Demo.SettingsItem {
                    title: I18n.tr("Font style")
                    titleColor: picker.colors.primaryText
                    Controls.SettingsSelect {
                        objectName: "font-style-select"
                        colors: picker.colors
                        model: picker.styles
                        currentIndex: picker.styles.indexOf(picker.selectedStyle)
                        onSelectionChanged: index => {
                            picker.selectedStyle = picker.styles[index];
                            picker.updateSelection();
                        }
                    }
                }
                Demo.SettingsItem {
                    title: I18n.tr("Font size")
                    titleColor: picker.colors.primaryText
                    Demo.SettingsTextField {
                        id: sizeInput
                        objectName: "font-size-input"
                        implicitWidth: 72
                        filled: true
                        horizontalAlignment: TextInput.AlignHCenter
                        validator: DoubleValidator { bottom: 4; top: 512; decimals: 1; locale: "en_US"; notation: DoubleValidator.StandardNotation }
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        Accessible.name: I18n.tr("Font size")
                        onTextEdited: picker.updateSelection()
                    }
                    Text { text: "pt"; color: picker.colors.secondaryText; font.pixelSize: 12 }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 76
                radius: 10
                color: picker.colors.card
                clip: true
                Text {
                    objectName: "font-selection-preview"
                    anchors.fill: parent
                    anchors.margins: 12
                    text: "Aa Bb 0123 · 中文字体"
                    font: picker.selectedFont
                    color: picker.colors.primaryText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            Demo.SettingsGroup {
                Layout.fillWidth: true
                visible: picker.category === "all"
                backgroundColor: picker.colors.card
                Repeater {
                    model: [
                        {label: I18n.tr("Font family"), key: "applyFamily"},
                        {label: I18n.tr("Font style"), key: "applyStyle"},
                        {label: I18n.tr("Font size"), key: "applySize"}
                    ]
                    delegate: Demo.SettingsItem {
                        required property var modelData
                        title: modelData.label
                        titleColor: picker.colors.primaryText
                        Controls.SettingsSwitch {
                            checked: picker[modelData.key]
                            accentColor: picker.colors.accent
                            onToggled: checked => picker[modelData.key] = checked
                        }
                    }
                }
            }
        }
    }
    footer: DialogButtonBox {
        padding: 24
        topPadding: 12
        spacing: 8
        background: Item { }
        Demo.LiquidDialogButton {
            text: I18n.tr("Cancel")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        Demo.LiquidDialogButton {
            objectName: "font-picker-confirm"
            text: I18n.tr("Choose")
            primaryAction: true
            enabled: picker.validSelection
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
}
