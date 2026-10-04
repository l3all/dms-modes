.pragma library

// Pure helpers shared by the daemon, bar widget and settings UI.

const EFFECT_KEYS = ["dnd", "theme", "nightLight", "powerProfile", "idleInhibit", "mute", "audioOutput", "audioInput"];

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function uid() {
    return "m" + Date.now().toString(36) + Math.random().toString(36).substring(2, 6);
}

function defaultEffects() {
    return {
        dnd: false,
        theme: "",
        nightLight: "",
        powerProfile: "",
        idleInhibit: false,
        mute: false,
        audioOutput: "", // PipeWire node name of the sink to switch to
        audioInput: ""   // PipeWire node name of the source to switch to
    };
}

function newMode(name) {
    return {
        id: uid(),
        name: name || "New mode",
        icon: "tune",
        scheduleEnabled: false,
        days: [1, 2, 3, 4, 5],
        start: "09:00",
        end: "17:00",
        effects: defaultEffects(),
        onEnter: "",
        onExit: ""
    };
}

function defaultModes() {
    return [
        {
            id: "dnd",
            name: "Do Not Disturb",
            icon: "do_not_disturb_on",
            scheduleEnabled: false,
            days: [0, 1, 2, 3, 4, 5, 6],
            start: "22:00",
            end: "07:00",
            effects: Object.assign(defaultEffects(), { dnd: true }),
            onEnter: "",
            onExit: ""
        },
        {
            id: "bedtime",
            name: "Bedtime",
            icon: "bedtime",
            scheduleEnabled: false,
            days: [0, 1, 2, 3, 4, 5, 6],
            start: "22:30",
            end: "07:00",
            effects: Object.assign(defaultEffects(), { dnd: true, theme: "dark", nightLight: "on", powerProfile: "power-saver" }),
            onEnter: "",
            onExit: ""
        },
        {
            id: "focus",
            name: "Focus",
            icon: "center_focus_strong",
            scheduleEnabled: false,
            days: [1, 2, 3, 4, 5],
            start: "09:00",
            end: "12:00",
            effects: Object.assign(defaultEffects(), { dnd: true, idleInhibit: true }),
            onEnter: "",
            onExit: ""
        },
        {
            id: "gaming",
            name: "Gaming",
            icon: "sports_esports",
            scheduleEnabled: false,
            days: [0, 1, 2, 3, 4, 5, 6],
            start: "20:00",
            end: "23:00",
            effects: Object.assign(defaultEffects(), { dnd: true, idleInhibit: true, powerProfile: "performance" }),
            onEnter: "",
            onExit: ""
        }
    ];
}

// Fill in any fields missing from a stored mode so older configs keep working.
function normalizeMode(m) {
    const base = newMode(m && m.name);
    const out = Object.assign(base, m || {});
    out.effects = Object.assign(defaultEffects(), (m && m.effects) || {});
    out.days = Array.isArray(out.days) ? out.days.map(Number) : base.days;
    return out;
}

function normalizeModes(list) {
    if (!Array.isArray(list) || list.length === 0)
        return defaultModes();
    return list.map(normalizeMode);
}

function parseTime(str) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(str || "").trim());
    if (!m)
        return -1;
    const h = Number(m[1]);
    const min = Number(m[2]);
    if (h > 23 || min > 59)
        return -1;
    return h * 60 + min;
}

function isValidTime(str) {
    return parseTime(str) >= 0;
}

function atMinutes(date, dayOffset, minutes) {
    const d = new Date(date.getFullYear(), date.getMonth(), date.getDate() + dayOffset, 0, 0, 0, 0);
    d.setMinutes(minutes);
    return d.getTime();
}

// Returns the end timestamp (ms) of the schedule window containing `now`, or 0 if
// the mode's schedule is not currently active. `days` lists the weekdays on which a
// window *starts*; overnight windows (end <= start) spill into the next day.
function scheduleWindowEnd(mode, now) {
    if (!mode || !mode.scheduleEnabled)
        return 0;
    const start = parseTime(mode.start);
    const end = parseTime(mode.end);
    if (start < 0 || end < 0)
        return 0;
    const days = mode.days || [];
    const date = new Date(now);
    const today = date.getDay();
    const yesterday = (today + 6) % 7;
    const nowMin = date.getHours() * 60 + date.getMinutes();

    if (end > start) {
        if (days.indexOf(today) !== -1 && nowMin >= start && nowMin < end)
            return atMinutes(date, 0, end);
        return 0;
    }
    if (days.indexOf(today) !== -1 && nowMin >= start)
        return atMinutes(date, 1, end);
    if (days.indexOf(yesterday) !== -1 && nowMin < end)
        return atMinutes(date, 0, end);
    return 0;
}

// Merge the effects of all active modes. Modes earlier in the list take priority
// for choice-valued effects; boolean effects apply if any active mode enables them.
// Returns {key: value} only for effects that are actually controlled.
function mergeEffects(modes, activeIds) {
    const desired = {};
    for (let i = 0; i < modes.length; i++) {
        const m = modes[i];
        if (activeIds.indexOf(m.id) === -1)
            continue;
        const e = m.effects || {};
        if (e.dnd)
            desired.dnd = true;
        if (e.idleInhibit)
            desired.idleInhibit = true;
        if (e.mute)
            desired.mute = true;
        if (e.theme && desired.theme === undefined)
            desired.theme = e.theme;
        if (e.nightLight && desired.nightLight === undefined)
            desired.nightLight = e.nightLight;
        if (e.powerProfile && desired.powerProfile === undefined)
            desired.powerProfile = e.powerProfile;
        if (e.audioOutput && desired.audioOutput === undefined)
            desired.audioOutput = e.audioOutput;
        if (e.audioInput && desired.audioInput === undefined)
            desired.audioInput = e.audioInput;
    }
    return desired;
}

function describeEffects(mode) {
    const e = (mode && mode.effects) || {};
    const parts = [];
    if (e.dnd)
        parts.push("Silence notifications");
    if (e.theme)
        parts.push(e.theme === "dark" ? "Dark theme" : "Light theme");
    if (e.nightLight)
        parts.push(e.nightLight === "on" ? "Night light" : "Night light off");
    if (e.powerProfile)
        parts.push({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" }[e.powerProfile] || e.powerProfile);
    if (e.idleInhibit)
        parts.push("Keep awake");
    if (e.mute)
        parts.push("Mute audio");
    if (e.audioOutput)
        parts.push("Switch output");
    if (e.audioInput)
        parts.push("Switch input");
    return parts.join(" · ");
}

function describeDays(days) {
    const set = (days || []).slice().sort();
    if (set.length === 7)
        return "Every day";
    if (set.length === 0)
        return "Never";
    if (set.join(",") === "1,2,3,4,5")
        return "Weekdays";
    if (set.join(",") === "0,6")
        return "Weekends";
    return set.map(d => DAY_LABELS[d]).join(", ");
}

function describeSchedule(mode) {
    if (!mode || !mode.scheduleEnabled)
        return "";
    return describeDays(mode.days) + ", " + mode.start + "–" + mode.end;
}

function formatClock(ts) {
    const d = new Date(ts);
    const h = d.getHours();
    const m = d.getMinutes();
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
}

function describeActivation(info) {
    if (!info)
        return "";
    if (info.until > 0)
        return "Until " + formatClock(info.until);
    return "Until you turn it off";
}
