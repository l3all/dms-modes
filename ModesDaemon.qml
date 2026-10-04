import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "ModesLogic.js" as Logic

// Background engine: owns activation state, evaluates schedules, applies and
// restores system effects, and exposes an IPC interface. The bar widget and
// settings talk to it through the "engine" plugin global var.
PluginComponent {
    id: root

    readonly property var modes: Logic.normalizeModes(pluginData.modes)
    readonly property bool showToasts: pluginData.showToasts ?? true

    // {modeId: {source: "manual" | "schedule", until: ms (0 = indefinitely)}}
    property var active: ({})
    // {modeId: ms} — scheduled window the user turned off early; don't re-enter it.
    property var snoozed: ({})
    // {effectKey: value} — system value captured before a mode took control of it.
    property var snapshot: ({})
    // {effectKey: value} — what the engine last applied.
    property var applied: ({})

    property bool _loaded: false

    readonly property string statePath: Paths.strip(Paths.state) + "/modes-state.json"

    FileView {
        id: stateFile
        path: root.statePath
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    Component.onCompleted: {
        loadState();
        PluginService.setGlobalVar(pluginId || "modes", "engine", root);
        Qt.callLater(evaluate);
    }

    Component.onDestruction: {
        PluginService.setGlobalVar(pluginId || "modes", "engine", null);
    }

    onModesChanged: {
        if (_loaded)
            Qt.callLater(evaluate);
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.evaluate()
    }

    // --- Public API (used by widget, settings and IPC) -----------------------

    function findMode(idOrName) {
        const key = String(idOrName || "").toLowerCase();
        return modes.find(m => m.id.toLowerCase() === key) || modes.find(m => m.name.toLowerCase() === key) || null;
    }

    function isActive(id) {
        return active[id] !== undefined;
    }

    // durationMinutes: 0/undefined = until turned off (or until the current schedule
    // window ends, matching Android behaviour), > 0 = for that many minutes.
    function activate(id, durationMinutes) {
        const mode = findMode(id);
        if (!mode)
            return false;
        const now = Date.now();
        const minutes = Number(durationMinutes) || 0;
        const windowEnd = Logic.scheduleWindowEnd(mode, now);
        const next = Object.assign({}, active);
        next[mode.id] = {
            source: "manual",
            until: minutes > 0 ? now + minutes * 60000 : windowEnd
        };
        const nextSnoozed = Object.assign({}, snoozed);
        delete nextSnoozed[mode.id];
        snoozed = nextSnoozed;
        commit(next);
        return true;
    }

    function deactivate(id) {
        const mode = findMode(id);
        if (!mode || !isActive(mode.id))
            return false;
        const windowEnd = Logic.scheduleWindowEnd(mode, Date.now());
        if (windowEnd > 0) {
            const nextSnoozed = Object.assign({}, snoozed);
            nextSnoozed[mode.id] = windowEnd;
            snoozed = nextSnoozed;
        }
        const next = Object.assign({}, active);
        delete next[mode.id];
        commit(next);
        return true;
    }

    function toggle(id, durationMinutes) {
        const mode = findMode(id);
        if (!mode)
            return false;
        return isActive(mode.id) ? deactivate(mode.id) : activate(mode.id, durationMinutes);
    }

    function deactivateAll() {
        const ids = Object.keys(active);
        ids.forEach(id => deactivate(id));
        return ids.length;
    }

    // --- Engine ---------------------------------------------------------------

    function evaluate() {
        const now = Date.now();
        const next = Object.assign({}, active);
        const nextSnoozed = {};
        let changed = false;

        for (const id in snoozed) {
            if (snoozed[id] > now)
                nextSnoozed[id] = snoozed[id];
        }

        for (const id in next) {
            const mode = modes.find(m => m.id === id);
            if (!mode || (next[id].until > 0 && next[id].until <= now)) {
                delete next[id];
                changed = true;
            }
        }

        modes.forEach(mode => {
            const windowEnd = Logic.scheduleWindowEnd(mode, now);
            if (windowEnd <= 0 || next[mode.id] || nextSnoozed[mode.id])
                return;
            next[mode.id] = {
                source: "schedule",
                until: windowEnd
            };
            changed = true;
        });

        snoozed = nextSnoozed;
        if (changed || !_loaded) {
            _loaded = true;
            commit(next);
        } else {
            publish();
        }
    }

    function commit(next) {
        const before = Object.keys(active);
        const after = Object.keys(next);
        active = next;

        const entered = after.filter(id => before.indexOf(id) === -1);
        const exited = before.filter(id => after.indexOf(id) === -1);

        applyEffects();

        exited.forEach(id => onModeExited(id));
        entered.forEach(id => onModeEntered(id));

        saveState();
        publish();
    }

    function onModeEntered(id) {
        const mode = modes.find(m => m.id === id);
        if (!mode)
            return;
        if (mode.onEnter)
            Quickshell.execDetached(["sh", "-c", mode.onEnter]);
        if (showToasts)
            ToastService.showInfo(mode.name + " is on", Logic.describeActivation(active[id]), "", "modes");
    }

    function onModeExited(id) {
        const mode = modes.find(m => m.id === id);
        if (!mode)
            return;
        if (mode.onExit)
            Quickshell.execDetached(["sh", "-c", mode.onExit]);
        if (showToasts)
            ToastService.showInfo(mode.name + " is off", "", "", "modes");
    }

    function applyEffects() {
        const desired = Logic.mergeEffects(modes, Object.keys(active));
        const nextSnapshot = Object.assign({}, snapshot);
        const nextApplied = {};

        for (const key in desired) {
            if (!(key in nextSnapshot))
                nextSnapshot[key] = readEffect(key);
            if (applied[key] !== desired[key])
                writeEffect(key, desired[key]);
            nextApplied[key] = desired[key];
        }

        for (const key in nextSnapshot) {
            if (key in desired)
                continue;
            writeEffect(key, nextSnapshot[key]);
            delete nextSnapshot[key];
        }

        snapshot = nextSnapshot;
        applied = nextApplied;
    }

    function readEffect(key) {
        switch (key) {
        case "dnd":
            return SessionData.doNotDisturb;
        case "theme":
            return SessionData.isLightMode ? "light" : "dark";
        case "nightLight":
            return DisplayService.nightModeEnabled ? "on" : "off";
        case "powerProfile":
            return typeof PowerProfiles !== "undefined" ? PowerProfileWatcher.profileSlug(PowerProfiles.profile) : "";
        case "idleInhibit":
            return SessionData.idleInhibited;
        case "mute":
            return AudioService.sink?.audio?.muted ?? false;
        case "audioOutput":
            return AudioService.sink?.name ?? "";
        case "audioInput":
            return AudioService.source?.name ?? "";
        }
        return undefined;
    }

    function writeEffect(key, value) {
        switch (key) {
        case "dnd":
            if (SessionData.doNotDisturb !== !!value)
                SessionData.setDoNotDisturb(!!value);
            break;
        case "theme":
            if (value === "light" || value === "dark") {
                const light = value === "light";
                if (SessionData.isLightMode !== light)
                    Theme.setLightMode(light, true, true);
            }
            break;
        case "nightLight":
            if (value === "on" && !DisplayService.nightModeEnabled)
                DisplayService.enableNightMode();
            else if (value === "off" && DisplayService.nightModeEnabled)
                DisplayService.disableNightMode();
            break;
        case "powerProfile":
            if (value && PowerProfileWatcher.available)
                PowerProfileWatcher.applyProfile(PowerProfileWatcher.parseProfileSlug(value));
            break;
        case "idleInhibit":
            SessionData.setIdleInhibited(!!value);
            break;
        case "mute":
            if (AudioService.sink?.audio)
                AudioService.sink.audio.muted = !!value;
            break;
        case "audioOutput":
            if (value && AudioService.sink?.name !== value && !AudioService.setDefaultSinkByName(value))
                console.warn("Modes: audio output not available:", value);
            break;
        case "audioInput":
            if (value && AudioService.source?.name !== value && !AudioService.setDefaultSourceByName(value))
                console.warn("Modes: audio input not available:", value);
            break;
        }
    }

    // --- Persistence & sharing -------------------------------------------------

    function loadState() {
        try {
            const text = stateFile.text();
            if (!text)
                return;
            const s = JSON.parse(text);
            active = s.active || {};
            snoozed = s.snoozed || {};
            snapshot = s.snapshot || {};
            applied = s.applied || {};
        } catch (e) {
            console.warn("Modes: failed to read state:", e);
        }
    }

    function saveState() {
        stateFile.setText(JSON.stringify({
            active: active,
            snoozed: snoozed,
            snapshot: snapshot,
            applied: applied
        }, null, 2));
    }

    function publish() {
        PluginService.setGlobalVar(pluginId || "modes", "active", active);
    }

    // --- IPC: dms ipc call modes <fn> [args] ------------------------------------

    IpcHandler {
        target: "modes"

        function list(): string {
            return root.modes.map(m => (root.isActive(m.id) ? "* " : "  ") + m.id + "\t" + m.name).join("\n");
        }

        function status(): string {
            const ids = Object.keys(root.active);
            if (ids.length === 0)
                return "none";
            return ids.map(id => {
                const m = root.modes.find(x => x.id === id);
                return (m ? m.name : id) + " (" + Logic.describeActivation(root.active[id]) + ")";
            }).join("\n");
        }

        function on(mode: string): string {
            return root.activate(mode, 0) ? "ok" : "unknown mode: " + mode;
        }

        function onFor(mode: string, minutes: string): string {
            return root.activate(mode, Number(minutes)) ? "ok" : "unknown mode: " + mode;
        }

        function off(mode: string): string {
            return root.deactivate(mode) ? "ok" : "not active: " + mode;
        }

        function toggle(mode: string): string {
            return root.toggle(mode, 0) ? "ok" : "unknown mode: " + mode;
        }

        function offAll(): string {
            return "deactivated " + root.deactivateAll();
        }
    }
}
