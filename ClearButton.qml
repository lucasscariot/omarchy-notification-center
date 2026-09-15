import QtQuick
import QtQuick.Controls
import qs.Commons

Rectangle {
    id: root

    property string help: label
    property string label: "Clear"
    readonly property bool iconOnly: label === "×"

    signal clicked

    Accessible.name: help
    Accessible.role: Accessible.Button
    ToolTip.delay: 600
    ToolTip.text: root.help
    ToolTip.visible: area.containsMouse
    activeFocusOnTab: true
    border.color: Color.accent
    border.width: activeFocus ? 1 : 0
    color: area.containsMouse ? Qt.alpha(Color.popups.text, 0.10) : (iconOnly ? "transparent" : Qt.alpha(Color.popups.text, 0.045))
    implicitHeight: 30
    implicitWidth: iconOnly ? 30 : Math.max(30, text.implicitWidth + 20)
    radius: 14

    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    Text {
        id: text

        anchors.centerIn: parent
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: 11
        text: root.label
        visible: !root.iconOnly
    }
    Item {
        anchors.centerIn: parent
        width: 12
        height: 12
        visible: root.iconOnly
        Repeater {
            model: [45, -45]
            Rectangle {
                required property int modelData
                anchors.centerIn: parent
                width: 12
                height: 1.25
                radius: 0.625
                rotation: modelData
                antialiasing: true
                color: Qt.alpha(Color.popups.text, area.containsMouse ? 0.9 : 0.55)
            }
        }
    }
    MouseArea {
        id: area

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: root.clicked()
    }
}
