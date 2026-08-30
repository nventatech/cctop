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

PlasmoidItem {
    id: root

    // ----------------- design tokens (graphite + petrol) -----------------
    // the palette is fixed dark by default; following the Plasma theme keeps
    // the popup readable on light desktops
    readonly property bool sysTheme: Plasmoid.configuration.followSystemTheme
    // overlay of the theme's text color, used to derive surfaces and borders
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

    // privacy mode: replace every money value with dots (eye button in the header)
    readonly property bool hideValues: Plasmoid.configuration.privacy

    // donation link (heart button in the header; hidden while empty)
    property string donateUrl: "https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD"

    // ----------------- i18n -----------------
    // empty setting = follow the system locale (pt_* -> pt_BR, es_* -> es)
    function systemLang() {
        var n = Qt.locale().name
        if (n.indexOf("pt") === 0) return "pt_BR"
        if (n.indexOf("es") === 0) return "es"
        return "en"
    }
    readonly property string lang: Plasmoid.configuration.language || systemLang()
    readonly property var strings: ({
        en: {
            loading: "loading…", month: "this month", today: "today",
            session: "CURRENT SESSION", weeklyAll: "ALL MODELS", weeklyModel: "MODEL",
            resets: "resets", inWord: "in", thisWindow: "this window",
            noSession: "no live data", subs: "SUBSCRIPTIONS", subsTotal: "Total",
            perMonth: "/mo", tipMonth: "this month", tipSession: "session",
            hist: "RECENT SESSIONS", budget: "budget", projected: "projected",
            topProjects: "TOP PROJECTS", prevMonth: "last month",
            byModel: "BY MODEL", months6: "LAST 6 MONTHS",
            extra: "EXTRA USAGE", credits: "credits", pace: "at this pace",
            limitFull: "hits 100%", updated: "updated", agoSuffix: "ago",
            stale: "collector failed, showing last data",
            d7: "last 7 days", d30: "last 30 days", apiEq: "API-equivalent",
            planValue: "plan value", limitReset: "limit reset", exportCsv: "export CSV",
            atReset: "at reset", justNow: "just now"
        },
        pt_BR: {
            loading: "carregando…", month: "este mês", today: "hoje",
            session: "SESSÃO ATUAL", weeklyAll: "TODOS OS MODELOS", weeklyModel: "MODELO",
            resets: "reseta", inWord: "em", thisWindow: "nesta janela",
            noSession: "sem dados ao vivo", subs: "ASSINATURAS", subsTotal: "Total",
            perMonth: "/mês", tipMonth: "neste mês", tipSession: "sessão",
            hist: "SESSÕES RECENTES", budget: "orçamento", projected: "projeção",
            topProjects: "TOP PROJETOS", prevMonth: "mês passado",
            byModel: "POR MODELO", months6: "ÚLTIMOS 6 MESES",
            extra: "USO EXTRA", credits: "créditos", pace: "neste ritmo",
            limitFull: "bate 100%", updated: "atualizado há", agoSuffix: "",
            stale: "coleta falhou, mostrando último dado",
            d7: "últimos 7 dias", d30: "últimos 30 dias", apiEq: "equivalente em API",
            planValue: "do plano", limitReset: "limite resetou", exportCsv: "exportar CSV",
            atReset: "no reset", justNow: "agora"
        },
        es: {
            loading: "cargando…", month: "este mes", today: "hoy",
            session: "SESIÓN ACTUAL", weeklyAll: "TODOS LOS MODELOS", weeklyModel: "MODELO",
            resets: "se reinicia", inWord: "en", thisWindow: "en esta ventana",
            noSession: "sin datos en vivo", subs: "SUSCRIPCIONES", subsTotal: "Total",
            perMonth: "/mes", tipMonth: "en este mes", tipSession: "sesión",
            hist: "SESIONES RECIENTES", budget: "presupuesto", projected: "proyección",
            topProjects: "TOP PROYECTOS", prevMonth: "mes pasado",
            byModel: "POR MODELO", months6: "ÚLTIMOS 6 MESES",
            extra: "USO EXTRA", credits: "créditos", pace: "a este ritmo",
            limitFull: "llega a 100%", updated: "actualizado hace", agoSuffix: "",
            stale: "la recolección falló, mostrando el último dato",
            d7: "últimos 7 días", d30: "últimos 30 días", apiEq: "equivalente en API",
            planValue: "del plan", limitReset: "límite reiniciado", exportCsv: "exportar CSV",
            atReset: "al reinicio", justNow: "ahora"
        }
    })
    readonly property var localeNames: ({ en: "en_US", pt_BR: "pt_BR", es: "es_ES" })
    function tr(key) { return (strings[lang] || strings.en)[key] }

    // ----------------- state -----------------
    property var providers: []
    property real costMonth: 0
    property real costToday: 0
    property real cost7d: 0
    property real cost30d: 0
    // claude alone, for the plan value line (the subscription is claude's)
    property real claudeMonth: 0
    property var block: null
    property var live: null
    property var subscription: null
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
    // last successful collection and whether the latest one failed; both
    // drive the footer status so stale numbers never look current
    property double lastUpdate: 0
    property bool fetchFailed: false
    readonly property int budgetM: Plasmoid.configuration.budgetMonthly
    readonly property real budgetPct: budgetM > 0 ? costMonth / budgetM * 100 : 0
    // end-of-month run rate from month-to-date spend
    readonly property real projectedMonth: {
        var d = new Date(now)
        var daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
        return costMonth / d.getDate() * daysInMonth
    }
    property bool loaded: false
    property double now: Date.now()

    // decoded and quoted so an install path with spaces still runs
    property string fetchScript: decodeURIComponent(Qt.resolvedUrl("../code/fetch.sh").toString().replace("file://", ""))
    // hard timeout so a hung collector never leaves the source stuck
    // (a stuck source silently swallows every later refresh request)
    property string fetchCmd: "timeout 55 bash '" + fetchScript + "'"
    property string exportScript: decodeURIComponent(Qt.resolvedUrl("../code/export.sh").toString().replace("file://", ""))

    // the big number follows the configured window; clicking it cycles
    readonly property var heroRanges: ["month", "today", "d7", "d30"]
    readonly property string heroRange: Plasmoid.configuration.heroRange || "month"
    function heroValue() {
        if (heroRange === "today") return costToday
        if (heroRange === "d7") return cost7d
        if (heroRange === "d30") return cost30d
        return costMonth
    }
    // the displayed figure eases towards the real one on every change
    property real heroShown: loaded ? heroValue() : 0
    Behavior on heroShown { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // today against yesterday, null while there is nothing to compare
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

    // ----------------- helpers -----------------
    function money(v) {
        if (hideValues) return "$•••"
        return "$" + v.toFixed(v >= 100 ? 0 : 2)
    }

    // credits come with their own currency, unlike the dollar costs in the logs
    function moneyCur(v, cur) {
        if (!cur || cur === "USD" || cur === "US$") return money(v)
        return cur + " " + (hideValues ? "•••" : v.toFixed(v >= 100 ? 0 : 2))
    }

    // green (0%) → yellow (~50%) → red (100%), like the Claude Code usage bar
    function sevColor(pct) {
        var t = Math.max(0, Math.min(1, pct / 100))
        return Qt.hsla((1 - t) * 0.33, 0.72, 0.58, 1)
    }

    // "claude-fable-5" -> "Fable 5", "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    function prettyModel(m) {
        var p = m.replace("claude-", "").split("-")
        if (p.length && /^\d{8}$/.test(p[p.length - 1])) p.pop()
        return p.map(function(s) { return s.charAt(0).toUpperCase() + s.slice(1) })
                .join(" ").replace(/(\d) (\d)/, "$1.$2")
    }

    // current model of a session: list is chronological, so the last
    // non-haiku entry is the one in use (background haiku calls filtered out)
    function mainModel(list) {
        list = list || []
        var main = list.filter(function(m) { return m.indexOf("haiku") < 0 })
        var pick = main.length ? main : list
        return pick.length ? prettyModel(pick[pick.length - 1]) : ""
    }
    function sessionModel() { return mainModel(sessionModels) }

    // the scoped weekly limit belongs to the model the API names, not to the
    // one in use: switching models must not relabel that bar. The API sends a
    // family name ("Fable"), so the local logs supply the version ("Fable 5").
    function scopedModelLabel(name) {
        if (!name) return sessionModel() || tr("weeklyModel")
        var seen = (models || []).map(function(m) { return m.name }).concat(sessionModels || [])
        for (var i = seen.length - 1; i >= 0; i--)
            if (seen[i].toLowerCase().indexOf(name.toLowerCase()) >= 0) return prettyModel(seen[i])
        return name
    }

    // the weekly limit closest to running out (all models vs each scoped one)
    function worstWeeklyPct() {
        if (!live) return 0
        var pct = live.weekly ? live.weekly.pct : 0
        var wm = live.weekly_models || []
        for (var i = 0; i < wm.length; i++) pct = Math.max(pct, wm[i].pct)
        return pct
    }

    // how long until the 5h window hits 100% at the current pace, "" when it
    // does not get there before the reset (or it is too early to extrapolate)
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

    // same extrapolation for a weekly window (it started 7 days before the
    // reset the API reports): {full: "2d 4h"} when the pace hits 100% before
    // the reset, {atReset: 62} otherwise, null when it is too early to tell
    function weeklyPace(data) {
        if (!data || !live || liveStale) return null
        var end = new Date(data.resets_at).getTime()
        var start = end - 7 * 24 * 3600 * 1000
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

    // the API stamps resets_at with the microsecond of the request, so the
    // string differs on every poll and can even cross a minute boundary:
    // round to the minute before it is used to identify a window
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

    // a window that was above the threshold and now reports a new reset time
    // has been freed: say so once, so the user knows they can go again
    function checkResets(prev, cur) {
        if (!prev || !cur) return
        var thS = Plasmoid.configuration.notifyThreshold
        var thW = Plasmoid.configuration.notifyThresholdWeekly
        if (thS > 0 && prev.session && cur.session
            && prev.session.resets_at !== cur.session.resets_at && prev.session.pct >= thS)
            notify("Claude " + tr("session").toLowerCase() + " · " + tr("limitReset"))
        if (thW <= 0) return
        var before = {}
        if (prev.weekly) before["all"] = prev.weekly
        var pw = prev.weekly_models || []
        for (var i = 0; i < pw.length; i++) before[pw[i].model || ("scoped" + i)] = pw[i]
        var checks = cur.weekly ? [{ key: "all", data: cur.weekly, label: tr("weeklyAll") }] : []
        var wm = cur.weekly_models || []
        for (var j = 0; j < wm.length; j++)
            checks.push({ key: wm[j].model || ("scoped" + j), data: wm[j],
                          label: scopedModelLabel(wm[j].model).toUpperCase() })
        for (var k = 0; k < checks.length; k++) {
            var old = before[checks[k].key]
            if (old && old.resets_at !== checks[k].data.resets_at && old.pct >= thW)
                notify(checks[k].label + " · " + tr("limitReset"))
        }
    }

    // single-quoted shell argument: notification text carries API and log data
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function notify(msg) {
        notifier.connectSource("notify-send -a cctop -i office-chart-bar cctop " + shq(msg))
    }

    // "3m" / "1h 05m" since the last successful collection
    function updatedText() {
        if (!lastUpdate) return ""
        var mins = Math.max(0, Math.round((now - lastUpdate) / 60000))
        if (mins === 0) return tr("justNow")
        var h = Math.floor(mins / 60), m = mins % 60
        var t = h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m"
        return tr("updated") + " " + t + (tr("agoSuffix") ? " " + tr("agoSuffix") : "")
    }

    // "1h 30m" until an ISO timestamp
    function timeLeft(iso) {
        var mins = Math.max(0, Math.round((new Date(iso).getTime() - now) / 60000))
        var h = Math.floor(mins / 60), m = mins % 60
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    // user-defined subscriptions from settings, one per line "Name: price"
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

    // panel label and dot share the severity color of the mode on display
    function compactColor() {
        var mode = Plasmoid.configuration.panelDisplay
        if (!live) return Kirigami.Theme.textColor
        if (mode === "weekly") return sevColor(worstWeeklyPct())
        if (["session", "reset"].indexOf(mode) >= 0) return sevColor(live.session.pct)
        return Kirigami.Theme.textColor
    }

    // panel label follows the configured display mode
    function compactText() {
        var mode = Plasmoid.configuration.panelDisplay
        if (mode === "today") return money(costToday)
        if (mode === "weekly") return live ? "w " + worstWeeklyPct() + "%" : "cc"
        if (mode === "subs") return hideValues ? "•••"
            : (subscription ? subscription.currency : "US$") + subsTotal()
        if (mode === "reset") return live ? timeLeft(live.session.resets_at) : "cc"
        return live ? live.session.pct + "%" : (block ? money(block.costUSD) : "cc")
    }

    // one desktop notification per 5h window when crossing the threshold.
    // The window's reset time is the key and it is stored in the config, so
    // a plasmashell restart does not repeat the notification
    function checkNotify() {
        var th = Plasmoid.configuration.notifyThreshold
        if (th <= 0 || !live || liveStale) return
        if (live.session.pct < th) return
        var key = String(live.session.resets_at || "")
        if (Plasmoid.configuration.notifiedSession === key) return
        Plasmoid.configuration.notifiedSession = key
        notify("Claude " + live.session.pct + "% · " + tr("resets") + " "
               + Qt.formatTime(new Date(live.session.resets_at), "HH:mm"))
    }

    // one notification per weekly window: all models, plus each scoped model
    function checkWeeklyNotify() {
        var th = Plasmoid.configuration.notifyThresholdWeekly
        if (th <= 0 || !live || liveStale) return
        var checks = [{ data: live.weekly, key: "all", label: tr("weeklyAll") }]
        var wm = live.weekly_models || []
        for (var i = 0; i < wm.length; i++)
            checks.push({ data: wm[i], key: wm[i].model || ("scoped" + i),
                          label: scopedModelLabel(wm[i].model).toUpperCase() })
        var flags = {}
        try { flags = JSON.parse(Plasmoid.configuration.notifiedWeekly || "{}") } catch (e) {}
        var changed = false
        for (var j = 0; j < checks.length; j++) {
            var c = checks[j]
            if (!c.data || c.data.pct < th) continue
            var key = String(c.data.resets_at || "")
            if (flags[c.key] === key) continue
            flags[c.key] = key
            changed = true
            notify(c.label + " " + c.data.pct + "% · " + tr("resets") + " "
                   + new Date(c.data.resets_at).toLocaleString(Qt.locale(localeNames[lang] || "en_US"), "ddd HH:mm"))
        }
        if (changed) Plasmoid.configuration.notifiedWeekly = JSON.stringify(flags)
    }

    // one notification per month at 80% and one at 100% of the budget;
    // the config keeps "YYYY-MM:<highest level notified>"
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

    // ===================== DATA =====================
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
                // token expired = live comes back null: keep showing the last
                // known limits (marked stale) instead of dropping the cards
                if (j.live) {
                    var lv = root.normalizeLive(j.live)
                    root.checkResets(root.live, lv)
                    root.live = lv
                    root.liveStale = false
                } else if (root.live) {
                    root.liveStale = true
                }
                root.subscription = j.subscription
                root.subscriptionOpenai = j.subscriptionOpenai || null
                root.sessionModels = j.sessionModels || []
                root.history = j.history || []
                root.spark = j.spark || []
                root.projects = (j.projects || []).filter(function(p) { return p.cost > 0 })
                // last bar = live claude month total (the collector cache lags);
                // right after a month turns, the collector may not list the new
                // month yet — append it instead of clobbering the previous bar
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

    // ===================== PANEL =====================
    compactRepresentation: MouseArea {
        Layout.preferredWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 4
        Layout.minimumWidth: Layout.preferredWidth
        onClicked: root.expanded = !root.expanded
        // scrolling over the panel widget cycles the display mode
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

    // ===================== POPUP =====================
    fullRepresentation: Item {
        id: fullRep
        Layout.preferredWidth: Kirigami.Units.gridUnit * 23
        Layout.preferredHeight: column.implicitHeight + Kirigami.Units.gridUnit + column.anchors.bottomMargin
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight
        // keeps the dialog from staying tall after the history card collapses
        Layout.maximumWidth: Layout.preferredWidth
        Layout.maximumHeight: Layout.preferredHeight

        readonly property int microSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.9)
        readonly property int smallSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.0)

        Rectangle { anchors.fill: parent; color: root.bgColor }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            // footer ToolButtons carry ~7px of internal bottom padding, so the
            // visual gap below them matches the top margin with less real margin
            anchors.bottomMargin: Math.round(Kirigami.Units.gridUnit * 0.6)
            spacing: Math.round(Kirigami.Units.gridUnit * 0.55)

            // ---------- header ----------
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

            // ---------- hero: monthly total ----------
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

                // previous month total + projected delta against it
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

                // monthly budget progress (only when a budget is configured)
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
                    // one provider fills the whole bar: nothing to compare
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

                // last 7 days (bars scale to the week's peak, today highlighted)
                Item {
                    id: sparkBox
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing * 2
                    visible: root.spark.length > 0
                    implicitHeight: Kirigami.Units.gridUnit * 3.2
                    property real peak: Math.max.apply(null, root.spark.map(function(s) { return s.c }).concat([0.01]))
                    // bars grow from the baseline each time the popup opens
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

            // ---------- top projects this month (toggled by the folder button) ----------
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

            // ---------- current session (live 5h limit) ----------
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

                    // pace warning: only when the current burn overshoots the window
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
                        visible: root.live === null && root.loaded
                        text: root.tr("noSession")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                    }
                }
            }

            // ---------- recent sessions (toggled by the history button) ----------
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

            // ---------- monthly history (toggled by the history button) ----------
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

            // ---------- weekly limits (live) ----------
            // two per row: accounts can have more than one scoped model limit
            GridLayout {
                Layout.fillWidth: true
                visible: root.live !== null
                columns: 2
                columnSpacing: Kirigami.Units.smallSpacing * 2
                rowSpacing: Kirigami.Units.smallSpacing * 2

                Repeater {
                    id: weeklyRep
                    model: {
                        if (!root.live) return []
                        var list = root.live.weekly ? [{ label: root.tr("weeklyAll"), data: root.live.weekly }] : []
                        var wm = root.live.weekly_models || []
                        for (var i = 0; i < wm.length; i++)
                            list.push({ label: root.scopedModelLabel(wm[i].model).toUpperCase(), data: wm[i] })
                        return list
                    }

                    Rectangle {
                        id: weeklyCard
                        Layout.fillWidth: true
                        // an odd last card spans the row instead of sitting half width
                        Layout.columnSpan: (index === weeklyRep.count - 1 && weeklyRep.count % 2 === 1) ? 2 : 1
                        readonly property bool wide: Layout.columnSpan === 2
                        radius: 12
                        color: root.surfaceColor
                        // the limit the API marks active is the one biting now
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
                                // half-width cards have no room for the "resets" word
                                PC3.Label {
                                    text: (weeklyCard.wide ? root.tr("resets") + " " : "")
                                          + new Date(modelData.data.resets_at).toLocaleString(Qt.locale(root.localeNames[root.lang] || "en_US"), "ddd HH:mm")
                                    color: root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                // pace at the current burn: when it hits 100%, or where it lands at the reset
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
                        }
                    }
                }
            }

            // ---------- extra usage credits (only when enabled on the account) ----------
            Rectangle {
                id: extraCard
                // extra_usage when the account has credits enabled, spend as
                // the fallback for accounts that only report the cash balance
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

            // ---------- subscriptions ----------
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
                    // what this month's claude usage would cost at API rates vs the plan
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

            // ---------- footer: utility actions ----------
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
