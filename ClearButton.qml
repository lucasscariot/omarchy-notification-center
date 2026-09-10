import QtQuick
import QtQuick.Controls
import qs.Commons

Rectangle {
    id: root

    property string help: label
    property string label: "Clear"

    signal clicked

    Accessible.name: help
    Accessible.role: Accessible.Button
    ToolTip.delay: 600
    ToolTip.text: root.help
    ToolTip.visible: area.containsMouse
    activeFocusOnTab: true
    border.color: Color.accent
    border.width: activeFocus ? 1 : 0
    color: area.containsMouse ? Qt.alpha(Color.foreground, 0.16) : Qt.alpha(Color.foreground, 0.07)
    implicitHeight: 28
    implicitWidth: text.implicitWidth + 18
    radius: 14

    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    Text {
        id: text

        anchors.centerIn: parent
        color: Color.foreground
        font.pixelSize: root.label === "×" ? 19 : 11
        text: root.label
    }
    MouseArea {
        id: area

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: root.clicked()
    }
}
