// cctop - AI usage/cost monitor for the KDE panel.
// Panel shows the live Claude session usage; the popup shows the monthly
// cost per provider, live session/weekly limits and subscriptions.
// All data is read locally (no accounts, no API keys).
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "strings.js" as Strings

PlasmoidItem {
    id: root

    readonly property bool sysTheme: Plasmoid.configuration.followSystemTheme
    function themeTint(a) {
        var t = Kirigami.Theme.textColor
        return Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(t.r, t.g, t.b, a))
    }
    property color bgColor: sysTheme ? Kirigami.Theme.backgroundColor : "#1a1a1d"
    property color surfaceColor: sysTheme ? themeTint(0.05) : "#242427"
    property color surface2Color: sysTheme ? themeTint(0.12) : "#2d2d31"
    property color borderColor: sysTheme ? themeTint(0.18) : "#34343a"
    property color textColor: sysTheme ? Kirigami.Theme.textColor : "#eaeaee"
    property color mutedColor: sysTheme ? Kirigami.Theme.disabledTextColor : "#909299"
    property color accentColor: sysTheme ? Kirigami.Theme.highlightColor : "#2a9fb8"
    property color okColor: "#4ade80"
    property color warnColor: "#fbbf24"
    property color alertColor: "#f2585f"

    readonly property bool hideValues: Plasmoid.configuration.privacy

    property string donateUrl: "https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD"

    function systemLang() {
        var n = Qt.locale().name
        if (n.indexOf("pt") === 0) return "pt_BR"
        if (n.indexOf("es") === 0) return "es"
        return "en"
    }
    readonly property string lang: Plasmoid.configuration.language || systemLang()
    readonly property var strings: Strings.dict
    readonly property var localeNames: ({ en: "en_US", pt_BR: "pt_BR", es: "es_ES" })
    function tr(key) { return (strings[lang] || strings.en)[key] }

    property var providers: []
    property real costMonth: 0
    property real costToday: 0
    property real cost7d: 0
    property real cost30d: 0
    property real claudeMonth: 0
    property var block: null
    property var live: null
    property var subscription: null
    property var liveOpenai: null
    property var subscriptionOpenai: null
    property var sessionModels: []
    property var history: []
    property var spark: []
    property var projects: []
    property var months: []
    property real prevMonth: 0
    property var models: []
    property bool showHistory: false
    property bool showProjects: false
    property bool liveStale: false
    property double lastUpdate: 0
    property bool fetchFailed: false
    readonly property int budgetM: Plasmoid.configuration.budgetMonthly
    readonly property real budgetPct: budgetM > 0 ? costMonth / budgetM * 100 : 0
    readonly property real projectedMonth: {
        var d = new Date(now)
        var daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
        return costMonth / d.getDate() * daysInMonth
    }
    property bool loaded: false
    property double now: Date.now()

    property string fetchScript: decodeURIComponent(Qt.resolvedUrl("../code/fetch.sh").toString().replace("file://", ""))
    property string fetchCmd: "timeout 55 bash '" + fetchScript + "'"
    property string exportScript: decodeURIComponent(Qt.resolvedUrl("../code/export.sh").toString().replace("file://", ""))

    readonly property var heroRanges: ["month", "today", "d7", "d30"]
    readonly property string heroRange: Plasmoid.configuration.heroRange || "month"
    function heroValue() {
        if (heroRange === "today") return costToday
        if (heroRange === "d7") return cost7d
        if (heroRange === "d30") return cost30d
        return costMonth
    }
    property real heroShown: loaded ? heroValue() : 0
    Behavior on heroShown { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    function todayDelta() {
        if (spark.length < 2) return null
        var y = spark[spark.length - 2].c
        if (!(y > 0)) return null
        return (costToday - y) / y * 100
    }

    function cycleHeroRange() {
        var i = heroRanges.indexOf(heroRange)
        Plasmoid.configuration.heroRange = heroRanges[(i + 1) % heroRanges.length]
    }

    function money(v) {
        if (hideValues) return "$•••"
        return "$" + v.toFixed(v >= 100 ? 0 : 2)
    }

    function moneyCur(v, cur) {
        if (!cur || cur === "USD" || cur === "US$") return money(v)
        return cur + " " + (hideValues ? "•••" : v.toFixed(v >= 100 ? 0 : 2))
    }

    function sevColor(pct) {
        var t = Math.max(0, Math.min(1, pct / 100))
        return Qt.hsla((1 - t) * 0.33, 0.72, 0.58, 1)
    }

    function prettyModel(m) {
        var p = m.replace("claude-", "").split("-")
        if (p.length && /^\d{8}$/.test(p[p.length - 1])) p.pop()
        return p.map(function(s) { return s.charAt(0).toUpperCase() + s.slice(1) })
                .join(" ").replace(/(\d) (\d)/, "$1.$2")
    }

    function mainModel(list) {
        list = list || []
        var main = list.filter(function(m) { return m.indexOf("haiku") < 0 })
        var pick = main.length ? main : list
        return pick.length ? prettyModel(pick[pick.length - 1]) : ""
    }
    function sessionModel() { return mainModel(sessionModels) }

    function scopedModelLabel(name) {
        if (!name) return sessionModel() || tr("weeklyModel")
        var seen = (models || []).map(function(m) { return m.name }).concat(sessionModels || [])
        for (var i = seen.length - 1; i >= 0; i--)
            if (seen[i].toLowerCase().indexOf(name.toLowerCase()) >= 0) return prettyModel(seen[i])
        return name
    }

    function worstWeeklyPct() {
        if (!live) return 0
        var pct = live.weekly ? live.weekly.pct : 0
        var wm = live.weekly_models || []
        for (var i = 0; i < wm.length; i++) pct = Math.max(pct, wm[i].pct)
        return pct
    }

    function timeToFull() {
        if (!live || !block || liveStale) return ""
        var start = new Date(block.startTime).getTime()
        var end = new Date(live.session.resets_at).getTime()
        var pct = live.session.pct
        if (isNaN(start) || isNaN(end) || pct <= 0 || now <= start) return ""
        var elapsed = now - start
        if (elapsed < (end - start) * 0.2) return ""
        var eta = elapsed * (100 - pct) / pct
        if (eta <= 0 || now + eta >= end) return ""
        return timeLeft(new Date(now + eta).toISOString())
    }

    function weeklyPace(data) {
        if (!data || (!live && !liveOpenai) || (live && liveStale && !data.minutes)) return null
        var end = new Date(data.resets_at).getTime()
        var start = end - (data.minutes ? data.minutes * 60000 : 7 * 24 * 3600 * 1000)
        var pct = data.pct
        if (isNaN(end) || pct <= 0 || now <= start || now >= end) return null
        var elapsed = now - start
        if (elapsed < (end - start) * 0.2) return null
        var eta = elapsed * (100 - pct) / pct
        if (now + eta >= end) return { atReset: Math.round(pct * (end - start) / elapsed) }
        var hours = Math.floor(eta / 3600000)
        var t = hours >= 24 ? Math.floor(hours / 24) + "d " + (hours % 24) + "h"
                            : timeLeft(new Date(now + eta).toISOString())
        return { full: t }
    }

    function roundReset(s) {
        var t = Date.parse(s)
        return isNaN(t) ? s : new Date(Math.round(t / 60000) * 60000).toISOString()
    }
    function normalizeLive(l) {
        var w = [l.session, l.weekly].concat(l.weekly_models || [])
        for (var i = 0; i < w.length; i++)
            if (w[i] && w[i].resets_at) w[i].resets_at = roundReset(w[i].resets_at)
        return l
    }

    // codex reports its quota windows with an explicit length instead of fixed
    // names, so the label comes from window_minutes
    function windowLabel(w) {
        if (!w || !w.minutes) return ""
        return w.minutes >= 1440 ? Math.round(w.minutes / 1440) + "D"
                                 : Math.round(w.minutes / 60) + "H"
    }

    function codexWindows() {
        if (!liveOpenai) return []
        var out = []
        var w = [liveOpenai.primary, liveOpenai.secondary]
        for (var i = 0; i < w.length; i++)
            if (w[i]) out.push({ label: ("Codex " + windowLabel(w[i])).toUpperCase(), data: w[i] })
        return out
    }

    function weeklyChecks(l) {
        var out = l && l.weekly ? [{ key: "all", data: l.weekly, label: tr("weeklyAll") }] : []
        var wm = (l && l.weekly_models) || []
        for (var i = 0; i < wm.length; i++)
            out.push({ key: wm[i].model || ("scoped" + i), data: wm[i],
                       label: scopedModelLabel(wm[i].model).toUpperCase() })
        return out
    }

    function resetLabel(iso) {
        var d = new Date(iso)
        if (isNaN(d.getTime())) return ""
        return d.getTime() - now < 24 * 3600 * 1000
            ? Qt.formatTime(d, "HH:mm")
            : d.toLocaleString(Qt.locale(localeNames[lang] || "en_US"), "ddd HH:mm")
    }

    function checkResets(prev, cur) {
        if (!prev || !cur) return
        var thS = Plasmoid.configuration.notifyThreshold
        var thW = Plasmoid.configuration.notifyThresholdWeekly
        if (thS > 0 && prev.session && cur.session
            && prev.session.resets_at !== cur.session.resets_at && prev.session.pct >= thS)
            notifyReset("Claude " + tr("session").toLowerCase(), cur.session)
        if (thW <= 0) return
        var before = {}
        var pw = weeklyChecks(prev)
        for (var i = 0; i < pw.length; i++) before[pw[i].key] = pw[i].data
        var checks = weeklyChecks(cur)
        for (var k = 0; k < checks.length; k++) {
            var old = before[checks[k].key]
            if (old && old.resets_at !== checks[k].data.resets_at && old.pct >= thW)
                notifyReset(checks[k].label, checks[k].data)
        }
    }
    function notifyReset(label, data) {
        notify(label + " · " + tr("limitReset") + " · " + data.pct + "% · "
               + tr("resets") + " " + resetLabel(data.resets_at))
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function notify(msg) {
        notifier.connectSource("notify-send -a cctop -i office-chart-bar cctop " + shq(msg))
    }

    function updatedText() {
        if (!lastUpdate) return ""
        var mins = Math.max(0, Math.round((now - lastUpdate) / 60000))
        if (mins === 0) return tr("justNow")
        var h = Math.floor(mins / 60), m = mins % 60
        var t = h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m"
        return tr("updated") + " " + t + (tr("agoSuffix") ? " " + tr("agoSuffix") : "")
    }

    function timeLeft(iso) {
        var mins = Math.max(0, Math.round((new Date(iso).getTime() - now) / 60000))
        var h = Math.floor(mins / 60), m = mins % 60
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    function extraSubscriptions() {
        var lines = (Plasmoid.configuration.extraSubscriptions || "").split("\n")
        var list = []
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^\s*(.+?)\s*:\s*(\d+(?:\.\d+)?)\s*$/)
            if (m) list.push({ name: m[1], price: Number(m[2]), currency: "US$" })
        }
        return list
    }

    function allSubscriptions() {
        var list = []
        if (subscription) list.push(subscription)
        if (subscriptionOpenai) list.push(subscriptionOpenai)
        return list.concat(extraSubscriptions())
    }

    function subsTotal() {
        var t = 0, list = allSubscriptions()
        for (var i = 0; i < list.length; i++) t += list[i].price
        return t
    }

    function compactColor() {
        var mode = Plasmoid.configuration.panelDisplay
        if (!live) return Kirigami.Theme.textColor
        if (mode === "weekly") return sevColor(worstWeeklyPct())
        if (["session", "reset"].indexOf(mode) >= 0) return sevColor(live.session.pct)
        return Kirigami.Theme.textColor
    }

    function compactText() {
        var mode = Plasmoid.configuration.panelDisplay
        if (mode === "today") return money(costToday)
        if (mode === "weekly") return live ? "w " + worstWeeklyPct() + "%" : "cc"
        if (mode === "subs") return hideValues ? "•••"
            : (subscription ? subscription.currency : "US$") + subsTotal()
        if (mode === "reset") return live ? timeLeft(live.session.resets_at) : "cc"
        return live ? live.session.pct + "%" : (block ? money(block.costUSD) : "cc")
    }

    function notifyLevel(pct, th) {
        var lv = 0
        var steps = [th, 95, 100]
        for (var i = 0; i < steps.length; i++)
            if (steps[i] >= th && pct >= steps[i] && steps[i] > lv) lv = steps[i]
        return lv
    }

    function levelKey(resetsAt, lv) { return String(resetsAt || "") + "|" + lv }
    function levelPending(saved, resetsAt, lv) {
        var p = String(saved || "").split("|")
        return !(p[0] === String(resetsAt || "") && Number(p[1]) >= lv)
    }

    function checkNotify() {
        var th = Plasmoid.configuration.notifyThreshold
        if (th <= 0 || !live || liveStale) return
        var lv = notifyLevel(live.session.pct, th)
        if (lv === 0) return
        var s = live.session
        if (!levelPending(Plasmoid.configuration.notifiedSession, s.resets_at, lv)) return
        Plasmoid.configuration.notifiedSession = levelKey(s.resets_at, lv)
        notify("Claude " + s.pct + "% · " + tr("resets") + " " + resetLabel(s.resets_at))
    }

    function checkWeeklyNotify() {
        var th = Plasmoid.configuration.notifyThresholdWeekly
        if (th <= 0 || !live || liveStale) return
        var checks = weeklyChecks(live)
        var flags = {}
        try { flags = JSON.parse(Plasmoid.configuration.notifiedWeekly || "{}") } catch (e) {}
        var changed = false
        for (var j = 0; j < checks.length; j++) {
            var c = checks[j]
            if (!c.data) continue
            var lv = notifyLevel(c.data.pct, th)
            if (lv === 0 || !levelPending(flags[c.key], c.data.resets_at, lv)) continue
            flags[c.key] = levelKey(c.data.resets_at, lv)
            changed = true
            notify(c.label + " " + c.data.pct + "% · " + tr("resets") + " "
                   + resetLabel(c.data.resets_at))
        }
        if (changed) Plasmoid.configuration.notifiedWeekly = JSON.stringify(flags)
    }

    function checkPaceNotify() {
        if (!live || liveStale) return
        var flags = {}
        try { flags = JSON.parse(Plasmoid.configuration.notifiedPace || "{}") } catch (e) {}
        var changed = false
        var thS = Plasmoid.configuration.notifyThreshold
        var eta = timeToFull()
        var s = live.session
        if (thS > 0 && eta !== "" && s.pct < thS
            && flags["session"] !== String(s.resets_at)) {
            flags["session"] = String(s.resets_at)
            changed = true
            notifyPace("Claude " + tr("session").toLowerCase(), eta)
        }
        var thW = Plasmoid.configuration.notifyThresholdWeekly
        if (thW > 0) {
            var checks = weeklyChecks(live)
            for (var i = 0; i < checks.length; i++) {
                var c = checks[i]
                var p = weeklyPace(c.data)
                if (!p || !p.full || c.data.pct >= thW) continue
                if (flags[c.key] === String(c.data.resets_at)) continue
                flags[c.key] = String(c.data.resets_at)
                changed = true
                notifyPace(c.label, p.full)
            }
        }
        if (changed) Plasmoid.configuration.notifiedPace = JSON.stringify(flags)
    }
    function notifyPace(label, eta) {
        notify(label + " · " + tr("pace") + ": " + tr("limitFull") + " "
               + tr("inWord") + " " + eta)
    }

    function checkLocked() {
        if (!live || liveStale) return
        var flags = {}
        try { flags = JSON.parse(Plasmoid.configuration.notifiedLocked || "{}") } catch (e) {}
        var changed = false
        var checks = [{ key: "session", data: live.session,
                        label: "Claude " + tr("session").toLowerCase() }]
                     .concat(weeklyChecks(live))
        for (var i = 0; i < checks.length; i++) {
            var c = checks[i]
            if (!c.data || !c.data.locked) continue
            if (flags[c.key] === String(c.data.resets_at)) continue
            flags[c.key] = String(c.data.resets_at)
            changed = true
            notify(c.label + " · " + tr("locked") + ": " + c.data.locked + " · "
                   + tr("resets") + " " + resetLabel(c.data.resets_at))
        }
        if (changed) Plasmoid.configuration.notifiedLocked = JSON.stringify(flags)
    }

    function checkBudget() {
        var b = Plasmoid.configuration.budgetMonthly
        if (b <= 0 || !loaded) return
        var pct = costMonth / b * 100
        var level = pct >= 100 ? 100 : (pct >= 80 ? 80 : 0)
        if (level === 0) return
        var d = new Date(now)
        var month = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
        var saved = (Plasmoid.configuration.notifiedBudget || "").split(":")
        if (saved[0] === month && Number(saved[1] || 0) >= level) return
        Plasmoid.configuration.notifiedBudget = month + ":" + level
        notify(Math.round(pct) + "% " + tr("budget") + " · " + money(costMonth) + " / " + money(b))
    }

    P5Support.DataSource {
        id: fetcher
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            try {
                var j = JSON.parse(data.stdout)
                root.providers = j.providers || []
                root.costMonth = j.totalMonth || 0
                root.costToday = j.totalToday || 0
                root.cost7d = j.total7d || 0
                root.cost30d = j.total30d || 0
                var cp = (j.providers || []).filter(function(p) { return p.id === "claude" })[0]
                root.claudeMonth = cp ? cp.costMonth : 0
                root.block = j.block
                if (j.live) {
                    var lv = root.normalizeLive(j.live)
                    root.checkResets(root.live, lv)
                    root.live = lv
                    root.liveStale = false
                } else if (root.live) {
                    root.liveStale = true
                }
                root.subscription = j.subscription
                root.liveOpenai = j.liveOpenai || null
                root.subscriptionOpenai = j.subscriptionOpenai || null
                root.sessionModels = j.sessionModels || []
                root.history = j.history || []
                root.spark = j.spark || []
                root.projects = (j.projects || []).filter(function(p) { return p.cost > 0 })
                var mh = j.months || []
                var claude = (j.providers || []).filter(function(p) { return p.id === "claude" })[0]
                if (claude) {
                    var d = new Date(root.now)
                    var curM = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
                    if (mh.length > 0 && mh[mh.length - 1].m === curM) {
                        mh[mh.length - 1].c = claude.costMonth
                    } else {
                        mh.push({ m: curM, c: claude.costMonth })
                        if (mh.length > 6) mh = mh.slice(-6)
                    }
                }
                root.months = mh
                root.prevMonth = j.prevMonth || 0
                root.models = (j.models || []).filter(function(m) { return m.cost > 0 })
                root.loaded = true
                root.lastUpdate = Date.now()
                root.fetchFailed = false
                root.checkNotify()
                root.checkWeeklyNotify()
                root.checkPaceNotify()
                root.checkLocked()
                root.checkBudget()
            } catch (e) { root.fetchFailed = true }
        }
    }

    P5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: function(source) { disconnectSource(source) }
    }

    Timer {
        interval: Math.max(30, Plasmoid.configuration.refreshInterval) * 1000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            fetcher.disconnectSource(root.fetchCmd)
            fetcher.connectSource(root.fetchCmd)
        }
    }

    toolTipMainText: "cctop"
    toolTipSubText: !loaded ? tr("loading")
        : money(costMonth) + " " + tr("tipMonth")
          + (live ? " · " + tr("tipSession") + " " + live.session.pct + "%" : "")
          + (fetchFailed ? "\n" + tr("stale") : "")

    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        Layout.preferredWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 4
        Layout.minimumWidth: Layout.preferredWidth
        onClicked: root.expanded = !root.expanded
        onWheel: function(wheel) {
            var modes = ["session", "weekly", "today", "subs", "reset"]
            var i = modes.indexOf(Plasmoid.configuration.panelDisplay)
            var next = (i + (wheel.angleDelta.y < 0 ? 1 : modes.length - 1)) % modes.length
            Plasmoid.configuration.panelDisplay = modes[next]
        }
        Row {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Rectangle {
                width: 7; height: 7; radius: 3.5
                anchors.verticalCenter: parent.verticalCenter
                visible: root.live !== null
                color: root.compactColor()
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            PC3.Label {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: root.compactText()
                font.family: "monospace"
                font.bold: true
                color: root.compactColor()
            }
        }
    }

    fullRepresentation: Item {
        id: fullRep
        Layout.preferredWidth: Kirigami.Units.gridUnit * 27
        Layout.preferredHeight: column.implicitHeight + Kirigami.Units.gridUnit + column.anchors.bottomMargin
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Layout.preferredHeight

        readonly property int microSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.9)
        readonly property int smallSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.0)

        Rectangle { anchors.fill: parent; color: root.bgColor }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            anchors.bottomMargin: Math.round(Kirigami.Units.gridUnit * 0.6)
            spacing: Math.round(Kirigami.Units.gridUnit * 0.55)

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2
                Kirigami.Icon {
                    source: Qt.resolvedUrl("../icons/cctop.svg")
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PC3.Label {
                    text: "cctop"
                    font.bold: true
                    color: root.textColor
                    font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.15)
                }
                PC3.Label {
                    text: new Date(root.now).toLocaleDateString(Qt.locale(root.localeNames[root.lang] || "en_US"), "dddd, d MMMM")
                    color: root.mutedColor
                    font.pixelSize: fullRep.microSize
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                }
                PC3.ToolButton {
                    icon.name: root.hideValues ? "view-hidden" : "view-visible"
                    checkable: true
                    checked: root.hideValues
                    onClicked: Plasmoid.configuration.privacy = checked
                }
                PC3.ToolButton {
                    icon.name: "folder-open-symbolic"
                    checkable: true
                    checked: root.showProjects
                    onClicked: root.showProjects = !root.showProjects
                }
                PC3.ToolButton {
                    icon.name: "view-history"
                    checkable: true
                    checked: root.showHistory
                    onClicked: root.showHistory = !root.showHistory
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    text: root.loaded ? root.money(root.heroShown) : "…"
                    color: root.textColor
                    font.pixelSize: Kirigami.Units.gridUnit * 2.4
                    font.bold: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cycleHeroRange()
                    }
                }
                RowLayout {
                    spacing: 0
                    PC3.Label {
                        text: root.tr(root.heroRange) + " ▾"
                        color: root.mutedColor
                        font.pixelSize: fullRep.smallSize
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleHeroRange()
                        }
                    }
                    PC3.Label {
                        text: root.heroRange === "month"
                            ? "  ·  " + root.tr("today") + " " + root.money(root.costToday)
                            : "  ·  " + root.tr("month") + " " + root.money(root.costMonth)
                        color: root.mutedColor
                        font.pixelSize: fullRep.smallSize
                    }
                    PC3.Label {
                        readonly property var delta: root.todayDelta()
                        visible: root.heroRange === "month" && delta !== null && !root.hideValues
                        text: " (" + (delta >= 0 ? "+" : "−") + Math.abs(Math.round(delta || 0)) + "%)"
                        color: delta > 0 ? root.sevColor(100) : root.sevColor(0)
                        font.pixelSize: fullRep.smallSize
                    }
                    PC3.Label {
                        visible: root.loaded && root.costMonth > 0
                        text: "  ·  " + root.tr("projected") + " ≈ " + root.money(root.projectedMonth)
                        color: root.budgetM > 0
                            ? root.sevColor(root.projectedMonth / root.budgetM * 100)
                            : root.mutedColor
                        font.pixelSize: fullRep.smallSize
                    }
                }

                RowLayout {
                    spacing: 0
                    visible: root.loaded && root.prevMonth > 0
                    PC3.Label {
                        text: root.tr("prevMonth") + " " + root.money(root.prevMonth)
                        color: root.mutedColor
                        font.pixelSize: fullRep.smallSize
                    }
                    PC3.Label {
                        readonly property real delta: (root.projectedMonth - root.prevMonth) / root.prevMonth * 100
                        visible: root.costMonth > 0 && !root.hideValues
                        text: "  ·  ≈ " + (delta >= 0 ? "+" : "−") + Math.abs(Math.round(delta)) + "%"
                        color: delta > 0 ? root.sevColor(100) : root.sevColor(0)
                        font.pixelSize: fullRep.smallSize
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    visible: root.budgetM > 0
                    spacing: Kirigami.Units.smallSpacing * 2
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: root.surface2Color
                        Rectangle {
                            width: parent.width * Math.min(1, root.budgetPct / 100)
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            height: parent.height
                            radius: 3
                            color: root.sevColor(root.budgetPct)
                        }
                    }
                    PC3.Label {
                        text: Math.round(root.budgetPct) + "% · " + root.money(root.budgetM) + " " + root.tr("budget")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    visible: root.providers.length > 1
                    height: 6
                    radius: 3
                    clip: true
                    color: root.surface2Color
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: root.providers
                            Rectangle {
                                height: parent.height
                                width: root.costMonth > 0 ? parent.width * (modelData.costMonth / root.costMonth) : 0
                                color: modelData.color
                            }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing * 3
                    Repeater {
                        model: root.providers
                        Row {
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: modelData.color
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PC3.Label {
                                text: modelData.name
                                color: root.textColor
                                font.pixelSize: fullRep.microSize
                                opacity: 0.9
                            }
                            PC3.Label {
                                text: root.money(modelData.costMonth)
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                        }
                    }
                }

                Item {
                    id: sparkBox
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing * 2
                    visible: root.spark.length > 0
                    implicitHeight: Kirigami.Units.gridUnit * 3.2
                    property real peak: Math.max.apply(null, root.spark.map(function(s) { return s.c }).concat([0.01]))
                    property real grow: 1
                    NumberAnimation on grow { from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic; running: root.expanded }

                    RowLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: root.spark
                            ColumnLayout {
                                id: sparkCol
                                Layout.fillWidth: true
                                spacing: 2
                                readonly property string dayName: new Date(modelData.d + "T12:00:00").toLocaleDateString(Qt.locale(root.localeNames[root.lang] || "en_US"), "ddd").slice(0, 3)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    MouseArea { id: sparkHover; anchors.fill: parent; hoverEnabled: true }
                                    PC3.ToolTip.visible: sparkHover.containsMouse
                                    PC3.ToolTip.text: sparkCol.dayName + " · " + root.money(modelData.c)
                                    PC3.ToolTip.delay: 300
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: Math.max(3, parent.height * (modelData.c / sparkBox.peak)) * sparkBox.grow
                                        radius: 2
                                        color: root.accentColor
                                        opacity: index === root.spark.length - 1 || sparkHover.containsMouse ? 1 : 0.5
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                    }
                                }
                                PC3.Label {
                                    text: sparkCol.dayName
                                    color: root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.showProjects && root.projects.length > 0
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: projCol.implicitHeight + Kirigami.Units.gridUnit * 1.2

                ColumnLayout {
                    id: projCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    PC3.Label {
                        text: root.tr("topProjects")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Repeater {
                        model: root.projects
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: modelData.name
                                color: root.textColor
                                font.pixelSize: fullRep.smallSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: root.costMonth > 0
                                    ? Math.round(modelData.cost / root.costMonth * 100) + "%"
                                    : ""
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                            PC3.Label {
                                text: root.money(modelData.cost)
                                color: root.mutedColor
                                font.pixelSize: fullRep.smallSize
                            }
                        }
                    }

                    PC3.Label {
                        visible: root.models.length > 0
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: root.tr("byModel")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Repeater {
                        model: root.models
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: root.prettyModel(modelData.name)
                                color: root.textColor
                                font.pixelSize: fullRep.smallSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: root.costMonth > 0
                                    ? Math.round(modelData.cost / root.costMonth * 100) + "%"
                                    : ""
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                            PC3.Label {
                                text: root.money(modelData.cost)
                                color: root.mutedColor
                                font.pixelSize: fullRep.smallSize
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: sessionCol.implicitHeight + Kirigami.Units.gridUnit * 1.2

                ColumnLayout {
                    id: sessionCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 2

                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            text: root.tr("session")
                            color: root.mutedColor
                            font.pixelSize: fullRep.microSize
                            font.letterSpacing: 0.5
                        }
                        PC3.Label {
                            text: root.sessionModel()
                            visible: text !== ""
                            color: root.accentColor
                            font.bold: true
                            font.pixelSize: fullRep.microSize
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PC3.Label {
                            text: root.live ? root.live.session.pct + "%" : "—"
                            font.bold: true
                            font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.45)
                            color: root.live ? root.sevColor(root.live.session.pct) : root.mutedColor
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: root.surface2Color
                        Rectangle {
                            width: parent.width * Math.min(1, root.live ? root.live.session.pct / 100 : 0)
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            height: parent.height
                            radius: 3
                            color: root.live ? root.sevColor(root.live.session.pct) : root.mutedColor
                        }
                    }

                    PC3.Label {
                        readonly property string eta: root.timeToFull()
                        Layout.fillWidth: true
                        visible: eta !== ""
                        text: root.tr("pace") + ": " + root.tr("limitFull") + " "
                              + root.tr("inWord") + " " + eta
                        color: root.sevColor(100)
                        font.pixelSize: fullRep.microSize
                        wrapMode: Text.WordWrap
                    }

                    PC3.Label {
                        Layout.fillWidth: true
                        visible: root.live !== null
                        text: root.live
                            ? root.tr("resets") + " " + Qt.formatTime(new Date(root.live.session.resets_at), "HH:mm")
                              + " (" + root.tr("inWord") + " " + root.timeLeft(root.live.session.resets_at) + ")"
                              + (root.block ? "  ·  " + root.money(root.block.costUSD) + " " + root.tr("thisWindow") : "")
                              + (root.liveStale ? "  ·  offline" : "")
                            : ""
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        wrapMode: Text.WordWrap
                    }
                    PC3.Label {
                        Layout.fillWidth: true
                        visible: root.live !== null && !!root.live.session.locked
                        text: root.live && root.live.session.locked
                            ? root.tr("locked") + ": " + root.live.session.locked : ""
                        color: root.alertColor
                        font.pixelSize: fullRep.microSize
                        wrapMode: Text.WordWrap
                    }

                    PC3.Label {
                        visible: root.live === null && root.loaded
                        text: root.tr("noSession")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.showHistory && root.history.length > 0
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: histCol.implicitHeight + Kirigami.Units.gridUnit * 1.6

                ColumnLayout {
                    id: histCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    PC3.Label {
                        text: root.tr("hist")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Repeater {
                        model: root.history
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: new Date(modelData.last).toLocaleString(Qt.locale(root.localeNames[root.lang] || "en_US"), "d MMM HH:mm")
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                            PC3.Label {
                                text: root.mainModel(modelData.models)
                                color: root.accentColor
                                font.bold: true
                                font.pixelSize: fullRep.microSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: root.money(modelData.cost)
                                color: root.textColor
                                font.pixelSize: fullRep.microSize
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.showHistory && root.months.length > 1
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: monthsCol.implicitHeight + Kirigami.Units.gridUnit * 1.2

                ColumnLayout {
                    id: monthsCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    PC3.Label {
                        text: root.tr("months6")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Item {
                        id: monthsBox
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 4
                        property real peak: Math.max.apply(null, root.months.map(function(m) { return m.c }).concat([0.01]))

                        RowLayout {
                            anchors.fill: parent
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: root.months
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    PC3.Label {
                                        text: root.money(modelData.c)
                                        color: root.mutedColor
                                        font.pixelSize: fullRep.microSize
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.max(3, parent.height * (modelData.c / monthsBox.peak))
                                            radius: 2
                                            color: root.accentColor
                                            opacity: index === root.months.length - 1 ? 1 : 0.5
                                        }
                                    }
                                    PC3.Label {
                                        text: new Date(modelData.m + "-15T12:00:00").toLocaleDateString(Qt.locale(root.localeNames[root.lang] || "en_US"), "MMM").slice(0, 3)
                                        color: root.mutedColor
                                        font.pixelSize: fullRep.microSize
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                visible: root.live !== null || root.liveOpenai !== null
                columns: 2
                columnSpacing: Kirigami.Units.smallSpacing * 2
                rowSpacing: Kirigami.Units.smallSpacing * 2

                Repeater {
                    id: weeklyRep
                    model: {
                        var list = []
                        if (root.live) {
                            if (root.live.weekly)
                                list.push({ label: root.tr("weeklyAll"), data: root.live.weekly })
                            var wm = root.live.weekly_models || []
                            for (var i = 0; i < wm.length; i++)
                                list.push({ label: root.scopedModelLabel(wm[i].model).toUpperCase(), data: wm[i] })
                        }
                        return list.concat(root.codexWindows())
                    }

                    Rectangle {
                        id: weeklyCard
                        Layout.fillWidth: true
                        Layout.columnSpan: (index === weeklyRep.count - 1 && weeklyRep.count % 2 === 1) ? 2 : 1
                        readonly property bool wide: Layout.columnSpan === 2
                        radius: 12
                        color: root.surfaceColor
                        border.color: modelData.data.active ? root.sevColor(modelData.data.pct) : root.borderColor
                        border.width: modelData.data.active ? 2 : 1
                        implicitHeight: weeklyCol.implicitHeight + Kirigami.Units.gridUnit

                        ColumnLayout {
                            id: weeklyCol
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.gridUnit * 0.65
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                PC3.Label {
                                    text: modelData.label
                                    color: root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                    font.letterSpacing: 0.5
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PC3.Label {
                                    text: modelData.data.pct + "%"
                                    font.bold: true
                                    color: root.sevColor(modelData.data.pct)
                                    font.pixelSize: fullRep.smallSize
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: root.surface2Color
                                Rectangle {
                                    width: parent.width * Math.min(1, modelData.data.pct / 100)
                                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    height: parent.height
                                    radius: 3
                                    color: root.sevColor(modelData.data.pct)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                PC3.Label {
                                    text: (weeklyCard.wide ? root.tr("resets") + " " : "")
                                          + new Date(modelData.data.resets_at).toLocaleString(Qt.locale(root.localeNames[root.lang] || "en_US"), "ddd HH:mm")
                                    color: root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PC3.Label {
                                    readonly property var pace: root.weeklyPace(modelData.data)
                                    visible: pace !== null
                                    text: !pace ? ""
                                        : pace.full ? "100% " + root.tr("inWord") + " " + pace.full
                                        : "≈" + pace.atReset + "% " + root.tr("atReset")
                                    color: pace && pace.full ? root.warnColor : root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                }
                            }
                            PC3.Label {
                                Layout.fillWidth: true
                                visible: !!modelData.data.locked
                                text: modelData.data.locked
                                    ? root.tr("locked") + ": " + modelData.data.locked : ""
                                color: root.alertColor
                                font.pixelSize: fullRep.microSize
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: extraCard
                readonly property var extra: root.live ? (root.live.extra || root.live.spend || null) : null
                readonly property real pct: extra ? extra.pct : 0
                Layout.fillWidth: true
                visible: extra !== null
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: extraCol.implicitHeight + Kirigami.Units.gridUnit

                ColumnLayout {
                    id: extraCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            text: root.tr("extra")
                            color: root.mutedColor
                            font.pixelSize: fullRep.microSize
                            font.letterSpacing: 0.5
                            Layout.fillWidth: true
                        }
                        PC3.Label {
                            text: Math.round(extraCard.pct) + "%"
                            font.bold: true
                            color: root.sevColor(extraCard.pct)
                            font.pixelSize: fullRep.smallSize
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: root.surface2Color
                        Rectangle {
                            width: parent.width * Math.min(1, extraCard.pct / 100)
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            height: parent.height
                            radius: 3
                            color: root.sevColor(extraCard.pct)
                        }
                    }
                    PC3.Label {
                        text: extraCard.extra
                            ? root.moneyCur(extraCard.extra.used || 0, extraCard.extra.currency)
                              + (extraCard.extra.limit
                                 ? " / " + root.moneyCur(extraCard.extra.limit, extraCard.extra.currency) : "")
                              + " " + root.tr("credits")
                            : ""
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.allSubscriptions().length > 0
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: subsCol.implicitHeight + Kirigami.Units.gridUnit * 1.2

                ColumnLayout {
                    id: subsCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    PC3.Label {
                        text: root.tr("subs")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Repeater {
                        model: root.allSubscriptions()
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: modelData.name
                                color: root.textColor
                                font.pixelSize: fullRep.smallSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: (root.hideValues ? modelData.currency + "•••"
                                    : modelData.currency + modelData.price) + root.tr("perMonth")
                                color: root.mutedColor
                                font.pixelSize: fullRep.smallSize
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderColor }
                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            text: root.tr("subsTotal")
                            font.bold: true
                            color: root.textColor
                            font.pixelSize: fullRep.smallSize
                            Layout.fillWidth: true
                        }
                        PC3.Label {
                            text: (root.subscription ? root.subscription.currency : "US$")
                                + (root.hideValues ? "•••" : root.subsTotal()) + root.tr("perMonth")
                            font.bold: true
                            color: root.accentColor
                            font.pixelSize: fullRep.smallSize
                        }
                    }
                    PC3.Label {
                        visible: root.subscription !== null && root.claudeMonth > 0 && root.subscription.price > 0
                        text: root.tr("apiEq") + " " + root.money(root.claudeMonth) + "  ·  "
                              + (root.hideValues ? "•••" : (root.claudeMonth / root.subscription.price).toFixed(1)) + "x " + root.tr("planValue")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PC3.ToolButton {
                    icon.name: "love"
                    visible: root.donateUrl !== ""
                    onClicked: Qt.openUrlExternally(root.donateUrl)
                }
                PC3.Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    text: root.fetchFailed ? root.tr("stale") : root.updatedText()
                    color: root.fetchFailed ? root.warnColor : root.mutedColor
                    font.pixelSize: fullRep.microSize
                    elide: Text.ElideRight
                }
                PC3.ToolButton {
                    icon.name: "document-export"
                    PC3.ToolTip.text: root.tr("exportCsv")
                    PC3.ToolTip.visible: hovered
                    onClicked: notifier.connectSource("bash '" + root.exportScript + "'")
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: {
                        fetcher.disconnectSource(root.fetchCmd)
                        fetcher.connectSource(root.fetchCmd)
                    }
                }
                PC3.ToolButton {
                    icon.name: "configure"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }
        }
    }
}
