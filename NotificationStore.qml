import QtQuick
import Quickshell.Io
import "NotificationGroups.js" as Groups

// Owns history I/O and optimistic dismissals. The panel owns presentation.
Item {
    id: root

    property var clearQueue: []
    readonly property int count: Groups.itemCount(notifications)
    property string errorMessage: ""
    property var hiddenIds: ({})
    readonly property string historyScript: Qt.resolvedUrl("backend/read_history.py").toString().replace(/^file:\/\//, "")
    property var notifications: []
    property bool previewing: false

    signal activationFailed
    signal activationRequested

    function activate(item) {
        if (activation.running || activateDelay.running)
            return;
        errorMessage = "";
        activation.command = command(["--activate", item.id]);
        activationRequested();
        activateDelay.start();
    }
    function applyGroups(groups) {
        notifications = Groups.visibleGroups(groups, hiddenIds);
    }
    function clearAll() {
        clearItems(Groups.itemIds(notifications));
    }
    function clearItems(ids) {
        errorMessage = "";
        var next = Object.assign({}, hiddenIds);
        ids.forEach(id => next[id] = true);
        hiddenIds = next;
        applyGroups(notifications);
        clearQueue.push(ids);
        clearNext();
    }
    function clearNext() {
        if (clearProcess.running || clearQueue.length === 0)
            return;
        clearProcess.ids = clearQueue.shift();
        clearProcess.command = command(["--clear", JSON.stringify(clearProcess.ids)]);
        clearProcess.running = true;
    }
    function command(args) {
        return ["/usr/bin/python", decodeURIComponent(historyScript)].concat(args);
    }
    function refresh() {
        if (!previewing && !history.running && !clearProcess.running)
            history.running = true;
    }

    Process {
        id: history

        command: root.command([])

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (!root.previewing)
                        root.applyGroups(JSON.parse(text));
                } catch (error) {
                    console.warn("notification-center: cannot read history");
                }
            }
        }
    }
    Process {
        id: clearProcess

        property var ids: []

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyGroups(JSON.parse(text));
                } catch (error) {
                    // The exit handler retries a history read after the queue drains.
                    console.warn("notification-center: cannot read cleared history");
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                var next = Object.assign({}, root.hiddenIds);
                ids.forEach(id => delete next[id]);
                root.hiddenIds = next;
                root.errorMessage = "Could not clear notifications. Please try again.";
            }
            Qt.callLater(function () {
                root.clearNext();
                root.refresh();
            });
        }
    }

    // Allow the drawer to release keyboard focus before activating an app.
    Timer {
        id: activateDelay

        interval: 50

        onTriggered: activation.running = true
    }
    Process {
        id: activation

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text);
                    if (!result.ok) {
                        root.errorMessage = result.error;
                        root.activationFailed();
                    }
                } catch (error) {
                    root.errorMessage = "Could not open this notification.";
                    root.activationFailed();
                }
            }
        }
    }
}
