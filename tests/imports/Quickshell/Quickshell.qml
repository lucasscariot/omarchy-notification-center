pragma Singleton
import QtQuick

// Quickshell's actual plugin is embedded in its executable. UI unit tests
// exercise fallback icons; runtime smoke tests must use the real executable.
QtObject {
    function iconPath(name, fallback) { return ""; }
}
