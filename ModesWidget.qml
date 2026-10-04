import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "ModesLogic.js" as Logic

PluginComponent {
    id: root

    readonly property var modes: Logic.normalizeModes(pluginData.modes)
    readonly property bool hideWhenInactive: pluginData.hideWhenInactive ?? false
    readonly property string pluginIcon: "routine"

    PluginGlobalVar {
        id: engineVar
        varName: "engine"
        defaultValue: null
    }

    PluginGlobalVar {
        id: activeVar
        varName: "active"
        defaultValue: ({})
    }

    readonly property var engine: engineVar.value
    readonly property var active: activeVar.value || {}
    readonly property var activeModes: modes.filter(m => active[m.id] !== undefined)
    readonly property bool anyActive: activeModes.length > 0
    readonly property var primaryMode: anyActive ? activeModes[0] : null

    // Minutes applied when turning a mode on from the popout; 0 = until turned off.
    property int pendingDuration: 0

    function toggleMode(id) {
        if (!engine) {
            ToastService.showError("Modes daemon is not running", "Re-enable the Modes plugin in Settings → Plugins.");
            return;
        }
        engine.toggle(id, pendingDuration);
    }

    // Open DMS Settings on the Plugins tab with this plugin's section expanded.
    // The settings window loads lazily, so wait for it before asking for the plugin.
    function openSettings() {
        closePopout();
        PopoutService.openSettingsWithTab("plugins");
        settingsWait.attempts = 0;
        settingsWait.restart();
    }

    Timer {
        id: settingsWait
        property int attempts: 0
        interval: 100
        repeat: true
        onTriggered: {
            const modal = PopoutService.settingsModal;
            if (modal || ++attempts > 30)
                stop();
            if (typeof modal?.openPluginSettings === "function")
                modal.openPluginSettings(root.pluginId || "modes");
        }
    }

    function statusText(mode) {
        const info = active[mode.id];
        if (info)
            return (info.source === "schedule" ? "Scheduled · " : "On · ") + Logic.describeActivation(info);
        const parts = [Logic.describeSchedule(mode), Logic.describeEffects(mode)].filter(s => s);
        return parts.join(" · ") || "No effects configured";
    }

    function updateVisibility() {
        if (hideWhenInactive)
            setVisibilityOverride(anyActive);
        else
            clearVisibilityOverride();
    }

    onAnyActiveChanged: updateVisibility()
    onHideWhenInactiveChanged: updateVisibility()
    Component.onCompleted: updateVisibility()

    // --- Control Center --------------------------------------------------------

    ccWidgetIcon: primaryMode ? primaryMode.icon : pluginIcon
    ccWidgetPrimaryText: primaryMode ? primaryMode.name : "Modes"
    ccWidgetSecondaryText: {
        if (activeModes.length > 1)
            return "+" + (activeModes.length - 1) + " more";
        if (primaryMode)
            return Logic.describeActivation(active[primaryMode.id]);
        return "Off";
    }
    ccWidgetIsActive: anyActive

    onCcWidgetToggled: {
        if (!engine)
            return;
        if (anyActive)
            engine.deactivateAll();
        else if (modes.length > 0)
            engine.activate(modes[0].id, 0);
    }

    // Approximate row and link heights; the detail panel scrolls if rows wrap.
    readonly property real rowHeight: Theme.iconSize + Theme.spacingM * 3
    readonly property real linkHeight: Theme.iconSize + Theme.spacingS
    ccDetailHeight: Math.min(modes.length, 5) * (rowHeight + Theme.spacingXS) + linkHeight + Theme.spacingM * 2
    ccDetailContent: Component {
        Rectangle {
            implicitHeight: ccList.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Column {
                id: ccList
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingXS

                Repeater {
                    model: root.modes
                    ModeRow {
                        width: ccList.width
                        host: root
                        mode: modelData
                    }
                }

                SettingsLink {
                    host: root
                }
            }
        }
    }

    // --- Bar pill ----------------------------------------------------------------

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.primaryMode ? root.primaryMode.icon : root.pluginIcon
                filled: !root.primaryMode
                size: root.iconSize
                color: root.anyActive ? Theme.primary : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.anyActive
                text: root.primaryMode ? root.primaryMode.name + (root.activeModes.length > 1 ? " +" + (root.activeModes.length - 1) : "") : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.primaryMode ? root.primaryMode.icon : root.pluginIcon
                filled: !root.primaryMode
                size: root.iconSize
                color: root.anyActive ? Theme.primary : Theme.surfaceVariantText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.activeModes.length > 1
                text: "+" + (root.activeModes.length - 1)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Popout ------------------------------------------------------------------

    popoutWidth: 380
    popoutContent: Component {
        PopoutComponent {
            headerText: "Modes"
            detailsText: root.anyActive ? root.activeModes.map(m => m.name).join(", ") + " on" : "No modes on"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Turn on for"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    DankButtonGroup {
                        id: durationGroup
                        readonly property var durations: [0, 30, 60, 120]
                        model: ["Until off", "30 min", "1 hr", "2 hr"]
                        size: "small"
                        currentIndex: Math.max(0, durations.indexOf(root.pendingDuration))
                        onSelectionChanged: (index, selected) => {
                            if (selected)
                                root.pendingDuration = durations[index];
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: root.modes
                        ModeRow {
                            width: parent.width
                            host: root
                            mode: modelData
                        }
                    }
                }

                DankButton {
                    visible: root.anyActive
                    width: parent.width
                    text: "Turn off all modes"
                    iconName: "block"
                    onClicked: root.engine?.deactivateAll()
                }

                SettingsLink {
                    host: root
                }
            }
        }
    }

    component ModeRow: StyledRect {
        id: row
        // Inline components can't see the outer file's ids, so the widget passes itself in.
        property var host
        property var mode
        readonly property bool on: host.active[mode.id] !== undefined

        height: Math.max(row.host.rowHeight, textColumn.implicitHeight + Theme.spacingM * 2)
        radius: Theme.cornerRadius
        color: on ? Theme.withAlpha(Theme.primary, 0.16) : (rowArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer)

        Rectangle {
            id: iconBubble
            width: Theme.iconSize + Theme.spacingM
            height: width
            radius: width / 2
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            color: row.on ? Theme.primary : Theme.surfaceContainerHighest

            DankIcon {
                anchors.centerIn: parent
                name: row.mode.icon
                size: Theme.iconSize - Theme.spacingXXS
                color: row.on ? Theme.primaryText : Theme.surfaceText
            }
        }

        Column {
            id: textColumn
            anchors.left: iconBubble.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: toggle.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                text: row.mode.name
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: row.host.statusText(row.mode)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.host.toggleMode(row.mode.id)
        }

        DankToggle {
            id: toggle
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            checked: row.on
            onToggled: row.host.toggleMode(row.mode.id)
        }
    }

    component SettingsLink: Item {
        id: link
        property var host

        implicitWidth: linkRow.implicitWidth
        implicitHeight: link.host.linkHeight
        width: implicitWidth
        height: implicitHeight

        Row {
            id: linkRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            DankIcon {
                name: "settings"
                size: Theme.iconSizeSmall
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "Edit modes in Settings"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                font.underline: linkArea.containsMouse
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: linkArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: link.host.openSettings()
        }
    }
}
