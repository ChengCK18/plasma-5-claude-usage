import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore

// Thin rounded bar; theme-colored track, caller-colored fill.
Item {
    id: bar
    property real value: 0      // 0..100
    property color color: PlasmaCore.Theme.highlightColor

    implicitHeight: Math.round(PlasmaCore.Units.smallSpacing * 1.5)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: PlasmaCore.Theme.textColor
        opacity: 0.12
    }
    Rectangle {
        width: Math.max(bar.value > 0 ? height : 0, parent.width * Math.min(bar.value, 100) / 100)
        height: parent.height
        radius: height / 2
        color: bar.color
        Behavior on width { NumberAnimation { duration: PlasmaCore.Units.longDuration; easing.type: Easing.OutCubic } }
    }
}
