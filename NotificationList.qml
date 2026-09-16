import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons

ListView {
    id: root
    readonly property real scrollbarGutter: 12
    property real scrollSpeed: 3
    property var expandedApps: ({})
    signal activateRequested(var item)
    signal clearRequested(var ids)
    signal toggleRequested(string key)
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    spacing: 16
    // Item.clip is rectangular. Mask the viewport so partially visible cards
    // retain curved edges at both ends of the scroll region.
    layer.enabled: true
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: Item {
            parent: root.parent
            width: root.width
            height: root.height
            layer.enabled: true
            visible: false
            Rectangle {
                width: parent.width - root.scrollbarGutter
                height: parent.height
                radius: 14
                color: "white"
            }
            // Keep the scrollbar in its own narrow, unmasked gutter.
            Rectangle {
                x: parent.width - 8
                width: 8
                height: parent.height
                color: "white"
            }
        }
    }
    // Preserve pixel deltas from touchpads, including their momentum events.
    // Scale only this drawer, not the user's compositor-wide scroll setting.
    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 48;
            if (delta === 0)
                return;
            root.cancelFlick();
            var end = root.originY + Math.max(0, root.contentHeight - root.height);
            root.contentY = Math.max(root.originY, Math.min(end, root.contentY - delta * root.scrollSpeed));
            event.accepted = true;
        }
    }
    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        visible: root.contentHeight > root.height + 1
        minimumSize: 0.08
        contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Qt.alpha(Color.popups.text, parent.pressed ? 0.5 : 0.22)
        }
    }
    delegate: AppStack {
        required property var modelData
        expanded: !!root.expandedApps[modelData.key]
        group: modelData
        height: implicitHeight
        width: ListView.view.width - root.scrollbarGutter
        onActivateRequested: item => root.activateRequested(item)
        onClearRequested: ids => root.clearRequested(ids)
        onToggleRequested: root.toggleRequested(modelData.key)
    }
}
