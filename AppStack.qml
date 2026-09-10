import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

Item {
    id: root

    readonly property int count: group.items.length
    property bool expanded: false
    required property var group
    readonly property string logo: {
        var icon = String(group.icon || "");
        if (icon.indexOf("file://") === 0)
            return icon;
        if (icon.charAt(0) === "/")
            return Qt.resolvedUrl("file://" + icon);
        if (icon && icon.indexOf("://") === -1)
            return Quickshell.iconPath(icon, true);
        return "";
    }

    signal activateRequested(var item)
    signal clearRequested(var ids)
    signal toggleRequested

    function openItem(item) {
        if (!expanded && count > 1)
            toggleRequested();
        else
            activateRequested(item);
    }

    implicitHeight: front.implicitHeight + (!expanded && count > 1 ? 9 : 0)

    // Consume clicks throughout the stack, including its padding and layered
    // edges, so they cannot reach the drawer's outside-click dismiss area.
    MouseArea {
        anchors.fill: parent
        cursorShape: !root.expanded && root.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: {
            if (!root.expanded && root.count > 1)
                root.toggleRequested();
        }
    }
    Rectangle {
        color: Qt.alpha(Color.foreground, 0.04)
        height: front.implicitHeight
        radius: 12
        visible: !root.expanded && root.count > 2
        width: parent.width - 24
        x: 12
        y: 9
    }
    Rectangle {
        color: Qt.alpha(Color.foreground, 0.06)
        height: front.implicitHeight
        radius: 12
        visible: !root.expanded && root.count > 1
        width: parent.width - 12
        x: 6
        y: 5
    }
    Rectangle {
        id: front

        border.color: Qt.alpha(Color.foreground, 0.06)
        border.width: 1
        color: Qt.darker(Color.background, 0.91)
        implicitHeight: content.implicitHeight + 28
        radius: 12
        width: parent.width

        ColumnLayout {
            id: content

            spacing: 12

            anchors {
                left: parent.left
                margins: 14
                right: parent.right
                top: parent.top
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    implicitHeight: 30
                    implicitWidth: 30

                    Image {
                        id: icon

                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: root.logo
                        sourceSize.height: 60
                        sourceSize.width: 60
                        visible: status === Image.Ready
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(Color.accent, 0.18)
                        radius: 8
                        visible: icon.status !== Image.Ready

                        Text {
                            anchors.centerIn: parent
                            color: Color.accent
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            text: root.group.app.charAt(0).toUpperCase()
                        }
                    }
                }
                Item {
                    Accessible.name: root.group.app + ", " + root.count + " notifications, " + (root.expanded ? "collapse" : "expand")
                    Accessible.role: Accessible.Button
                    Layout.fillWidth: true
                    activeFocusOnTab: root.count > 1
                    implicitHeight: 34

                    Keys.onReturnPressed: root.toggleRequested()
                    Keys.onSpacePressed: root.toggleRequested()

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: parent.width

                        Text {
                            color: Color.foreground
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            text: root.group.app
                            textFormat: Text.PlainText
                            width: parent.width
                        }
                        Text {
                            color: Color.muted
                            font.pixelSize: 11
                            text: root.count + " notifications  " + (root.expanded ? "⌃" : "⌄")
                            visible: root.count > 1
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.count > 1

                        onClicked: root.toggleRequested()
                    }
                }
                ClearButton {
                    help: "Clear " + root.group.app + " notifications"
                    label: "Clear"

                    onClicked: root.clearRequested(root.group.items.map(item => item.id))
                }
            }
            Repeater {
                model: root.expanded ? root.group.items : root.group.items.slice(0, 1)

                delegate: NotificationCard {
                    required property int index
                    required property var modelData

                    appName: root.group.app
                    count: root.count
                    expanded: root.expanded
                    item: modelData
                    separatorVisible: index > 0

                    onClearRequested: root.clearRequested([modelData.id])
                    onOpenRequested: root.openItem(modelData)
                }
            }
        }
    }
}
