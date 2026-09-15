import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
    id: root

    property date openedAt: new Date()
    property bool dragging: false
    property var expandedApps: ({})
    property bool inputEnabled: true
    property bool inputReady: false
    property bool opened: false
    property real progress: 0

    function close() {
        store.previewing = false;
        dragging = false;
        opened = false;
        progress = 0;
        if (connection.connected)
            connection.write("closed\n");
    }
    function open() {
        openedAt = new Date();
        store.refresh();
        dragging = false;
        opened = true;
        progress = 1;
        if (connection.connected)
            connection.write("opened\n");
    }
    function receive(data) {
        try {
            var event = JSON.parse(data);
            if (event.event === "ready") {
                inputReady = true;
                return;
            }
            if (event.event === "connected")
                return;
            if (event.event === "start") {
                dragging = true;
                store.refresh();
            }
            if (event.event === "finish") {
                dragging = false;
                opened = event.progress > 0.5;
            }
            progress = Math.max(0, Math.min(1, event.progress));
        } catch (error) {
            console.warn("notification-center: invalid gesture message");
        }
    }
    function toggleStack(key) {
        var next = Object.assign({}, expandedApps);
        next[key] = !next[key];
        expandedApps = next;
    }

    NotificationStore {
        id: store

        onActivationFailed: root.open()
        onActivationRequested: root.close()
    }
    Socket {
        id: connection

        connected: true
        path: "/run/omarchy-edge-notifications/socket"

        parser: SplitParser {
            onRead: data => root.receive(data)
        }

        onConnectionStateChanged: {
            if (connected) {
                write("ping\n");
                write(root.opened ? "opened\n" : "closed\n");
            } else if (root.inputReady)
                root.close();
            root.inputReady = false;
        }
        onError: {
            connected = false;
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: true

        onTriggered: {
            if (connection.connected)
                connection.write("ping\n");
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: true

        onTriggered: {
            if (root.inputEnabled && !connection.connected)
                connection.connected = true;
            if (root.opened || root.dragging)
                store.refresh();
        }
    }
    IpcHandler {
        function close(): void {
            root.close();
        }
        function expandApp(key: string): void {
            root.toggleStack(key);
        }
        function open(): void {
            root.open();
        }
        // Enables a non-input visual check of intermediate positions.
        function preview(value: real): void {
            store.refresh();
            root.dragging = true;
            root.progress = Math.max(0, Math.min(1, value));
        }
        function previewData(payload: string): void {
            store.previewing = true;
            store.notifications = JSON.parse(Qt.atob(payload));
            root.opened = true;
            root.progress = 1;
        }
        function resume(): void {
            root.inputEnabled = true;
            connection.connected = true;
        }
        function status(): string {
            return JSON.stringify({
                version: 2,
                connected: connection.connected,
                ready: root.inputReady,
                opened: root.opened,
                progress: root.progress,
                apps: store.notifications.length
            });
        }
        function suspend(): void {
            root.inputEnabled = false;
            connection.connected = false;
            root.close();
        }

        target: "notification-center"
    }
    PanelWindow {
        id: surface

        // Keep the closing surface interactive until it unmaps. Switching to None
        // mid-animation makes Hyprland refocus the old window beneath this layer,
        // even if the user has since switched workspaces. OnDemand allows other
        // windows to take focus without waiting for the closing animation.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lucasscariot-notification-center"
        color: "transparent"
        exclusiveZone: 0
        screen: Quickshell.screens.find(s => s.name === "eDP-1") || Quickshell.screens[0]
        visible: root.progress > 0.001 || root.dragging

        anchors {
            bottom: true
            left: true
            right: true
            top: true
        }
        Item {
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.close()

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.progress * 0.04

                MouseArea {
                    anchors.fill: parent

                    onClicked: root.close()
                }
            }
            Rectangle {
                id: drawer

                border.color: Color.popups.border
                border.width: 1
                clip: true
                color: Color.popups.background
                height: Math.max(0, surface.height - y - 16)
                radius: 20
                width: Math.min(430, surface.width - 32)
                x: surface.width - (width + 16) * root.progress
                y: 44

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 20

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                color: Qt.alpha(Color.popups.text, 0.55)
                                font.family: Style.font.family
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                font.letterSpacing: 1.2
                                text: Qt.formatDateTime(root.openedAt, "dddd, d MMMM").toUpperCase()
                            }
                            Text {
                                Layout.fillWidth: true
                                color: Color.popups.text
                                font.family: Style.font.family
                                font.pixelSize: 28
                                font.weight: Font.DemiBold
                                text: "Notifications"
                            }
                        }
                        ClearButton {
                            help: "Close notification center"
                            label: "×"
                            onClicked: root.close()
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.alpha(Color.popups.text, 0.09)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: store.notifications.length > 0

                        Text {
                            Layout.fillWidth: true
                            color: Qt.alpha(Color.popups.text, 0.6)
                            font.family: Style.font.family
                            font.pixelSize: 12
                            text: store.count + (store.count === 1 ? " notification" : " notifications") + " · " + store.notifications.length + (store.notifications.length === 1 ? " app" : " apps")
                        }
                        ClearButton {
                            help: "Clear all notifications from the center"
                            label: "Clear all"

                            onClicked: store.clearAll()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        color: Color.urgent
                        font.pixelSize: 12
                        text: store.errorMessage
                        visible: store.errorMessage.length > 0
                        wrapMode: Text.Wrap
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: store.notifications.length === 0 && store.errorMessage.length === 0
                        Column {
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 12
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 64
                                height: 64
                                radius: 32
                                color: Qt.alpha(Color.accent, 0.10)
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: Color.accent
                                    font.family: Style.font.family
                                    font.pixelSize: 28
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "All caught up"
                                color: Color.popups.text
                                font.family: Style.font.family
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "New notifications will appear here."
                                color: Qt.alpha(Color.popups.text, 0.55)
                                font.family: Style.font.family
                                font.pixelSize: 13
                            }
                        }
                    }
                    NotificationList {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        model: store.notifications
                        visible: store.notifications.length > 0
                        expandedApps: root.expandedApps
                        onActivateRequested: item => store.activate(item)
                        onClearRequested: ids => store.clearItems(ids)
                        onToggleRequested: key => root.toggleStack(key)
                    }
                }
            }
        }
    }
}
