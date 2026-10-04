import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "ModesLogic.js" as Logic

PluginSettings {
    id: root
    pluginId: "modes"

    property var modes: Logic.normalizeModes(pluginService ? pluginService.loadPluginData("modes", "modes", []) : [])
    property string expandedId: ""

    readonly property var themeOptions: [
        { label: "Don't change", value: "" },
        { label: "Dark", value: "dark" },
        { label: "Light", value: "light" }
    ]
    readonly property var nightLightOptions: [
        { label: "Don't change", value: "" },
        { label: "On", value: "on" },
        { label: "Off", value: "off" }
    ]
    readonly property var powerOptions: [
        { label: "Don't change", value: "" },
        { label: "Power saver", value: "power-saver" },
        { label: "Balanced", value: "balanced" },
        { label: "Performance", value: "performance" }
    ]

    function reloadModes() {
        modes = Logic.normalizeModes(pluginService ? pluginService.loadPluginData("modes", "modes", []) : []);
    }

    onPluginServiceChanged: reloadModes()

    Connections {
        target: root.pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === "modes")
                root.reloadModes();
        }
    }

    function saveModes(list) {
        modes = list;
        if (pluginService)
            pluginService.savePluginData("modes", "modes", list);
    }

    function updateMode(id, patch) {
        saveModes(modes.map(m => m.id === id ? Object.assign({}, m, patch) : m));
    }

    function updateEffect(id, key, value) {
        const mode = modes.find(m => m.id === id);
        if (!mode)
            return;
        const effects = Object.assign({}, mode.effects);
        effects[key] = value;
        updateMode(id, { effects: effects });
    }

    function moveMode(id, delta) {
        const list = modes.slice();
        const i = list.findIndex(m => m.id === id);
        const j = i + delta;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        const tmp = list[i];
        list[i] = list[j];
        list[j] = tmp;
        saveModes(list);
    }

    function removeMode(id) {
        saveModes(modes.filter(m => m.id !== id));
    }

    function addMode() {
        const mode = Logic.newMode("New mode");
        expandedId = mode.id;
        saveModes(modes.concat([mode]));
    }

    // Dropdown options for PipeWire devices. A saved device that isn't currently
    // connected is kept in the list so the setting isn't silently lost.
    function deviceOptions(nodes, current) {
        const opts = [{ label: "Don't change", value: "" }];
        const seen = {};
        for (const node of nodes) {
            if (!node?.name)
                continue;
            let label = AudioService.displayName(node) || node.name;
            if (seen[label])
                label += " (" + node.name + ")";
            seen[label] = true;
            opts.push({ label: label, value: node.name });
        }
        if (current && !opts.some(o => o.value === current))
            opts.push({ label: current + " (unavailable)", value: current });
        return opts;
    }

    function labelFor(options, value) {
        const o = options.find(x => x.value === (value || ""));
        return o ? o.label : options[0].label;
    }

    function valueFor(options, label) {
        const o = options.find(x => x.label === label);
        return o ? o.value : "";
    }

    StyledText {
        width: parent.width
        text: "Modes"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Modes bundle system changes — silencing notifications, audio devices, theme, night light, power profile and more — that you can switch on manually or on a schedule. When several modes are on, ones higher in the list win."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showToasts"
        label: "Show toasts"
        description: "Show a toast when a mode turns on or off"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "hideWhenInactive"
        label: "Hide bar widget when no mode is on"
        defaultValue: false
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            model: root.modes

            StyledRect {
                id: card
                required property var modelData
                required property int index
                readonly property var mode: modelData
                readonly property bool expanded: root.expandedId === mode.id

                width: parent.width
                height: cardColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: cardColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // Header
                    Item {
                        width: parent.width
                        height: Theme.iconSize + Theme.spacingL

                        DankIcon {
                            id: headerIcon
                            name: card.mode.icon
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.left: headerIcon.right
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: headerButtons.left
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                width: parent.width
                                text: card.mode.name
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: [Logic.describeSchedule(card.mode), Logic.describeEffects(card.mode)].filter(s => s).join(" · ") || "No effects"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.left: parent.left
                            anchors.right: headerButtons.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expandedId = card.expanded ? "" : card.mode.id
                        }

                        Row {
                            id: headerButtons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            DankActionButton {
                                iconName: "arrow_upward"
                                tooltipText: "Higher priority"
                                visible: card.index > 0
                                onClicked: root.moveMode(card.mode.id, -1)
                            }
                            DankActionButton {
                                iconName: "arrow_downward"
                                tooltipText: "Lower priority"
                                visible: card.index < root.modes.length - 1
                                onClicked: root.moveMode(card.mode.id, 1)
                            }
                            DankActionButton {
                                iconName: card.expanded ? "expand_less" : "expand_more"
                                onClicked: root.expandedId = card.expanded ? "" : card.mode.id
                            }
                        }
                    }

                    // Editor
                    Column {
                        visible: card.expanded
                        width: parent.width
                        spacing: Theme.spacingM

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            DankTextField {
                                width: (parent.width - Theme.spacingM) * 0.6
                                labelText: "Name"
                                text: card.mode.name
                                onEditingFinished: {
                                    if (text.trim() && text !== card.mode.name)
                                        root.updateMode(card.mode.id, { name: text.trim() });
                                }
                            }

                            DankTextField {
                                width: (parent.width - Theme.spacingM) * 0.4
                                labelText: "Icon (Material Symbols)"
                                leftIconName: text || "help"
                                text: card.mode.icon
                                onEditingFinished: {
                                    if (text.trim() && text !== card.mode.icon)
                                        root.updateMode(card.mode.id, { icon: text.trim() });
                                }
                            }
                        }

                        SectionLabel { text: "Schedule" }

                        DankToggle {
                            width: parent.width
                            text: "Turn on automatically"
                            description: "Activate during the chosen days and times"
                            checked: card.mode.scheduleEnabled
                            onToggled: checked => root.updateMode(card.mode.id, { scheduleEnabled: checked })
                        }

                        Column {
                            visible: card.mode.scheduleEnabled
                            width: parent.width
                            spacing: Theme.spacingS

                            Row {
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: [1, 2, 3, 4, 5, 6, 0]

                                    Rectangle {
                                        required property int modelData
                                        readonly property bool selected: card.mode.days.indexOf(modelData) !== -1
                                        width: Theme.iconSize + Theme.spacingL
                                        height: width
                                        radius: width / 2
                                        color: selected ? Theme.primary : Theme.surfaceContainerHighest

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: Logic.DAY_LABELS[parent.modelData].substring(0, 2)
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: parent.selected ? Theme.primaryText : Theme.surfaceText
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const d = parent.modelData;
                                                const days = card.mode.days.slice();
                                                const i = days.indexOf(d);
                                                if (i === -1)
                                                    days.push(d);
                                                else
                                                    days.splice(i, 1);
                                                root.updateMode(card.mode.id, { days: days });
                                            }
                                        }
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingM

                                DankTextField {
                                    width: (parent.width - Theme.spacingM) / 2
                                    labelText: "Start (HH:MM)"
                                    placeholderText: "22:00"
                                    text: card.mode.start
                                    onEditingFinished: {
                                        if (Logic.isValidTime(text))
                                            root.updateMode(card.mode.id, { start: text.trim() });
                                        else
                                            text = card.mode.start;
                                    }
                                }

                                DankTextField {
                                    width: (parent.width - Theme.spacingM) / 2
                                    labelText: "End (HH:MM)"
                                    placeholderText: "07:00"
                                    text: card.mode.end
                                    onEditingFinished: {
                                        if (Logic.isValidTime(text))
                                            root.updateMode(card.mode.id, { end: text.trim() });
                                        else
                                            text = card.mode.end;
                                    }
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: "An end time earlier than the start runs overnight into the next day."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                            }
                        }

                        SectionLabel { text: "While this mode is on" }

                        DankToggle {
                            width: parent.width
                            text: "Silence notifications"
                            description: "Turn on Do Not Disturb"
                            checked: card.mode.effects.dnd
                            onToggled: checked => root.updateEffect(card.mode.id, "dnd", checked)
                        }

                        DankToggle {
                            width: parent.width
                            text: "Keep awake"
                            description: "Inhibit idle, screen lock and suspend"
                            checked: card.mode.effects.idleInhibit
                            onToggled: checked => root.updateEffect(card.mode.id, "idleInhibit", checked)
                        }

                        DankToggle {
                            width: parent.width
                            text: "Mute audio"
                            description: "Mute the default output device"
                            checked: card.mode.effects.mute
                            onToggled: checked => root.updateEffect(card.mode.id, "mute", checked)
                        }

                        DankDropdown {
                            readonly property var deviceOpts: root.deviceOptions(AudioService.typedSinks, card.mode.effects.audioOutput)
                            width: parent.width
                            text: "Audio output"
                            description: "Switch the default output device"
                            options: deviceOpts.map(o => o.label)
                            currentValue: root.labelFor(deviceOpts, card.mode.effects.audioOutput)
                            onValueChanged: value => root.updateEffect(card.mode.id, "audioOutput", root.valueFor(deviceOpts, value))
                        }

                        DankDropdown {
                            readonly property var deviceOpts: root.deviceOptions(AudioService.typedSources, card.mode.effects.audioInput)
                            width: parent.width
                            text: "Audio input"
                            description: "Switch the default microphone"
                            options: deviceOpts.map(o => o.label)
                            currentValue: root.labelFor(deviceOpts, card.mode.effects.audioInput)
                            onValueChanged: value => root.updateEffect(card.mode.id, "audioInput", root.valueFor(deviceOpts, value))
                        }

                        DankDropdown {
                            width: parent.width
                            text: "Theme"
                            options: root.themeOptions.map(o => o.label)
                            currentValue: root.labelFor(root.themeOptions, card.mode.effects.theme)
                            onValueChanged: value => root.updateEffect(card.mode.id, "theme", root.valueFor(root.themeOptions, value))
                        }

                        DankDropdown {
                            width: parent.width
                            text: "Night light"
                            options: root.nightLightOptions.map(o => o.label)
                            currentValue: root.labelFor(root.nightLightOptions, card.mode.effects.nightLight)
                            onValueChanged: value => root.updateEffect(card.mode.id, "nightLight", root.valueFor(root.nightLightOptions, value))
                        }

                        DankDropdown {
                            width: parent.width
                            text: "Power profile"
                            options: root.powerOptions.map(o => o.label)
                            currentValue: root.labelFor(root.powerOptions, card.mode.effects.powerProfile)
                            onValueChanged: value => root.updateEffect(card.mode.id, "powerProfile", root.valueFor(root.powerOptions, value))
                        }

                        SectionLabel { text: "Commands" }

                        DankTextField {
                            width: parent.width
                            labelText: "Run when mode turns on"
                            placeholderText: "e.g. playerctl pause"
                            text: card.mode.onEnter
                            onEditingFinished: {
                                if (text !== card.mode.onEnter)
                                    root.updateMode(card.mode.id, { onEnter: text });
                            }
                        }

                        DankTextField {
                            width: parent.width
                            labelText: "Run when mode turns off"
                            placeholderText: "e.g. notify-send 'Welcome back'"
                            text: card.mode.onExit
                            onEditingFinished: {
                                if (text !== card.mode.onExit)
                                    root.updateMode(card.mode.id, { onExit: text });
                            }
                        }

                        DankButton {
                            text: "Delete mode"
                            iconName: "delete"
                            backgroundColor: Theme.surfaceContainerHighest
                            textColor: Theme.error
                            onClicked: root.removeMode(card.mode.id)
                        }
                    }
                }
            }
        }
    }

    Row {
        spacing: Theme.spacingM

        DankButton {
            text: "Add mode"
            iconName: "add"
            onClicked: root.addMode()
        }

        DankButton {
            text: "Reset to defaults"
            iconName: "restart_alt"
            backgroundColor: Theme.surfaceContainerHighest
            textColor: Theme.surfaceText
            onClicked: {
                root.expandedId = "";
                root.saveModes(Logic.defaultModes());
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Command line: dms ipc call modes list | status | on <mode> | onFor <mode> <minutes> | off <mode> | toggle <mode> | offAll"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    component SectionLabel: StyledText {
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }
}
