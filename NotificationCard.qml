import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
    id: notification

    required property string appName
    required property int count
    required property bool expanded
    required property var item
    property bool separatorVisible: false

    signal clearRequested
    signal openRequested

    Layout.fillWidth: true
    spacing: 8

    Rectangle {
        Layout.bottomMargin: 5
        Layout.fillWidth: true
        Layout.topMargin: 4
        color: Qt.alpha(Color.popups.text, 0.1)
        implicitHeight: 1
        visible: notification.separatorVisible
    }
    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            color: Qt.alpha(Color.popups.text, 0.5)
            font.family: Style.font.family
            font.pixelSize: 11
            text: Qt.formatDateTime(new Date(notification.item.timestamp), "ddd HH:mm")
        }
        ClearButton {
            help: "Clear this notification"
            implicitHeight: 22
            label: "×"
            visible: notification.expanded && notification.count > 1

            onClicked: notification.clearRequested()
        }
    }
    Text {
        Accessible.name: !notification.expanded && notification.count > 1 ? "Expand " + notification.appName + " notifications" : "Open " + notification.appName + ": " + text
        Accessible.role: !notification.expanded && notification.count > 1 ? Accessible.Button : Accessible.Link
        Layout.fillWidth: true
        activeFocusOnTab: true
        color: Color.popups.text
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: 14
        font.weight: Font.DemiBold
        maximumLineCount: notification.expanded ? 5 : 2
        text: notification.item.summary
        textFormat: Text.PlainText
        wrapMode: Text.Wrap

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            z: -1
            radius: 5
            color: parent.activeFocus ? Qt.alpha(Color.accent, 0.12) : "transparent"
            border.color: Color.accent
            border.width: parent.activeFocus ? 1 : 0
        }
        Keys.onReturnPressed: notification.openRequested()
        Keys.onSpacePressed: notification.openRequested()

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: notification.openRequested()
        }
    }
    Text {
        Layout.fillWidth: true
        color: Qt.alpha(Color.popups.text, 0.70)
        elide: Text.ElideRight
        font.family: Style.font.family
        font.pixelSize: 13
        maximumLineCount: notification.expanded ? 8 : 3
        text: notification.item.body
        textFormat: Text.PlainText
        visible: text.length > 0
        wrapMode: Text.Wrap

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onClicked: notification.openRequested()
        }
    }
}
