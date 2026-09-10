pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject font: QtObject {
        readonly property string family: "sans-serif"
    }
}
