import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.extras 2.0 as PlasmaExtras

Item {
    id: root

    property bool loading: true
    property bool ok: false
    property string error: ""
    property var limits: []
    property var models: ({ session: [], week: [] })
    property string updated: ""
    property string modelScope: "session"

    readonly property string helper: Qt.resolvedUrl("../code/usage.py").toString().replace(/^file:\/\//, "")
    readonly property real sessionPct: limits.length ? limits[0].percent : 0
    readonly property real worstPct: limits.reduce(function (m, l) { return Math.max(m, l.percent) }, 0)

    function severityColor(pct) {
        if (pct >= plasmoid.configuration.critThreshold) return PlasmaCore.Theme.negativeTextColor
        if (pct >= plasmoid.configuration.warnThreshold) return PlasmaCore.Theme.neutralTextColor
        return PlasmaCore.Theme.positiveTextColor
    }

    function familyColor(family) {
        switch (family) {
        case "opus": return "#d97757"
        case "sonnet": return "#6e9bf5"
        case "haiku": return "#4cc9b0"
        case "fable": return "#b48cf2"
        default: return PlasmaCore.Theme.disabledTextColor
        }
    }

    function refresh() {
        lastRefresh = Date.now()
        executable.connectSource("/usr/bin/python3 '" + helper + "'")
    }

    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation
    Plasmoid.icon: "utilities-system-monitor"
    Plasmoid.toolTipMainText: i18n("Claude Code usage")
    Plasmoid.toolTipSubText: {
        if (loading) return i18n("Loading…")
        if (!ok) return error
        return limits.map(function (l) { return l.label + ": " + Math.round(l.percent) + "%" }).join("\n")
               + (error ? "\n" + error : "")
    }

    property double lastRefresh: 0
    // Opening the popup refreshes, but at most once a minute to stay clear of rate limits.
    Plasmoid.onExpandedChanged: if (plasmoid.expanded && Date.now() - lastRefresh > 60000) refresh()

    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: {
            disconnectSource(sourceName)
            root.loading = false
            try {
                var d = JSON.parse(data["stdout"])
                root.ok = d.ok
                root.error = d.error
                root.limits = d.limits
                root.models = d.models
                root.updated = d.updated
            } catch (e) {
                root.ok = false
                root.error = i18n("Helper failed: %1", (data["stderr"] || String(e)).trim())
            }
        }
    }

    Timer {
        interval: Math.max(1, plasmoid.configuration.refreshMinutes) * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Plasmoid.compactRepresentation: MouseArea {
        readonly property bool vertical: plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: vertical ? -1 : badge.width + PlasmaCore.Units.smallSpacing * 2
        Layout.minimumHeight: vertical ? badge.height + PlasmaCore.Units.smallSpacing * 2 : -1
        hoverEnabled: true
        onClicked: plasmoid.expanded = !plasmoid.expanded

        Rectangle {
            id: badge
            anchors.centerIn: parent
            height: Math.min(parent.vertical ? parent.width : parent.height, PlasmaCore.Units.iconSizes.medium)
                    - PlasmaCore.Units.smallSpacing
            width: Math.max(height, badgeLabel.implicitWidth + PlasmaCore.Units.smallSpacing * 2)
            radius: PlasmaCore.Units.smallSpacing * 1.5
            color: root.ok ? root.severityColor(root.worstPct) : PlasmaCore.Theme.disabledTextColor
            opacity: parent.containsMouse ? 0.85 : 1

            PlasmaComponents3.Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.loading ? "…" : (root.ok ? Math.round(root.sessionPct) : "!")
                color: "white"
                font.bold: true
                font.pixelSize: badge.height * 0.55
            }
        }
    }

    Plasmoid.fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: PlasmaCore.Units.gridUnit * 18
        Layout.preferredWidth: PlasmaCore.Units.gridUnit * 20
        Layout.minimumHeight: content.implicitHeight + PlasmaCore.Units.largeSpacing * 2
        Layout.preferredHeight: Layout.minimumHeight
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 1
                    text: i18n("Claude Code usage")
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    PlasmaComponents3.ToolTip { text: i18n("Refresh") }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: PlasmaCore.Units.largeSpacing
            spacing: PlasmaCore.Units.largeSpacing

            // --- limits -----------------------------------------------------
            PlasmaComponents3.Label {
                visible: root.loading || root.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.ok ? PlasmaCore.Theme.neutralTextColor : PlasmaCore.Theme.negativeTextColor
                text: root.loading ? i18n("Loading…") : root.error
            }

            Repeater {
                model: root.limits
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: PlasmaCore.Units.smallSpacing
                    RowLayout {
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData.label
                            font.bold: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(modelData.percent) + "%"
                            font.bold: true
                            color: root.severityColor(modelData.percent)
                        }
                    }
                    UsageBar {
                        Layout.fillWidth: true
                        value: modelData.percent
                        color: root.severityColor(modelData.percent)
                    }
                    PlasmaComponents3.Label {
                        visible: text !== ""
                        text: modelData.reset
                        opacity: 0.6
                        font: PlasmaCore.Theme.smallestFont
                    }
                }
            }

            // --- per-model breakdown ----------------------------------------
            PlasmaCore.SvgItem {
                Layout.fillWidth: true
                elementId: "horizontal-line"
                svg: PlasmaCore.Svg { imagePath: "widgets/line" }
            }

            RowLayout {
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 5
                    text: i18n("By model")
                    opacity: 0.7
                }
                PlasmaComponents3.TabBar {
                    id: scopeTabs
                    Layout.preferredWidth: PlasmaCore.Units.gridUnit * 9
                    currentIndex: root.modelScope === "week" ? 1 : 0
                    PlasmaComponents3.TabButton {
                        text: i18n("Session")
                        onClicked: root.modelScope = "session"
                    }
                    PlasmaComponents3.TabButton {
                        text: i18n("Week")
                        onClicked: root.modelScope = "week"
                    }
                }
            }

            PlasmaComponents3.Label {
                visible: root.models[root.modelScope].length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.6
                font.italic: true
                text: i18n("No Claude Code activity on this machine in this window")
            }

            Repeater {
                model: root.models[root.modelScope]
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: PlasmaCore.Units.smallSpacing / 2
                    RowLayout {
                        Rectangle {
                            width: PlasmaCore.Units.smallSpacing * 2
                            height: width
                            radius: width / 2
                            color: root.familyColor(modelData.family)
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: modelData.name
                        }
                        PlasmaComponents3.Label {
                            text: i18n("%1 tok · %2%", modelData.tokensText, Math.round(modelData.share))
                            opacity: 0.75
                        }
                    }
                    UsageBar {
                        Layout.fillWidth: true
                        value: modelData.share
                        color: root.familyColor(modelData.family)
                    }
                }
            }

            PlasmaComponents3.Label {
                visible: root.updated !== ""
                text: i18n("Updated %1 · model data from local Claude Code logs", root.updated)
                opacity: 0.5
                font: PlasmaCore.Theme.smallestFont
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item { Layout.fillHeight: true }
        }
    }
}
