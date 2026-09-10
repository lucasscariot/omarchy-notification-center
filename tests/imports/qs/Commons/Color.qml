pragma Singleton
import QtQuick

// A deterministic theme for isolated UI tests, not a runtime replacement.
QtObject {
    readonly property color foreground: "#eeeeee"
    readonly property color background: "#222222"
    readonly property color accent: "#6699ff"
    readonly property color muted: "#aaaaaa"
    readonly property color urgent: "#ff6666"
}
