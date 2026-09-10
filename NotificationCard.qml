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
    spacing: 7

    Rectangle {
        Layout.bottomMargin: 5
        Layout.fillWidth: true
        Layout.topMargin: 4
        color: Qt.alpha(Color.foreground, 0.1)
        implicitHeight: 1
        visible: notification.separatorVisible
    }
    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            color: Color.muted
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
        color: Color.foreground
        elide: Text.ElideRight
        font.pixelSize: 14
        font.weight: Font.DemiBold
        maximumLineCount: notification.expanded ? 5 : 2
        text: notification.item.summary
        textFormat: Text.PlainText
        wrapMode: Text.Wrap

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
        color: Qt.alpha(Color.foreground, 0.8)
        elide: Text.ElideRight
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
