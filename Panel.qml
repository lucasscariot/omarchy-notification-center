import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
    id: root

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

    Behavior on progress {
        enabled: !root.dragging

        NumberAnimation {
            duration: 230
            easing.type: Easing.OutCubic
        }
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
                opacity: root.progress * 0.12

                MouseArea {
                    anchors.fill: parent

                    onClicked: root.close()
                }
            }
            Rectangle {
                id: drawer

                border.color: Qt.alpha(Color.foreground, 0.18)
                border.width: 1
                clip: true
                color: Color.background
                height: surface.height - 64
                radius: 18
                width: Math.min(390, surface.width - 24)
                x: surface.width - (width + 12) * root.progress
                y: 48

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            Layout.fillWidth: true
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: 21
                            font.weight: Font.DemiBold
                            text: "Notifications"
                        }
                        Rectangle {
                            color: closeArea.containsMouse ? Qt.alpha(Color.foreground, 0.16) : Qt.alpha(Color.foreground, 0.07)
                            implicitHeight: 30
                            implicitWidth: 30
                            radius: 15

                            Text {
                                anchors.centerIn: parent
                                color: Color.foreground
                                font.pixelSize: 22
                                text: "×"
                            }
                            MouseArea {
                                id: closeArea

                                anchors.fill: parent
                                hoverEnabled: true

                                onClicked: root.close()
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: store.notifications.length > 0

                        Text {
                            Layout.fillWidth: true
                            color: Color.muted
                            font.pixelSize: 12
                            text: store.count + " notifications"
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
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 36
                        color: Color.muted
                        font.pixelSize: 15
                        text: "You’re all caught up"
                        visible: store.notifications.length === 0
                    }
                    ListView {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        model: store.notifications
                        spacing: 14

                        delegate: AppStack {
                            required property var modelData

                            expanded: !!root.expandedApps[modelData.key]
                            group: modelData
                            height: implicitHeight
                            width: ListView.view.width

                            onActivateRequested: item => store.activate(item)
                            onClearRequested: ids => store.clearItems(ids)
                            onToggleRequested: root.toggleStack(modelData.key)
                        }
                    }
                }
            }
        }
    }
}
