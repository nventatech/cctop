// cctop - collector wrapper: runs fetch.sh, keeps the parsed state and
// raises the desktop notifications.
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as L from './logic.js';

Gio._promisify(Gio.Subprocess.prototype, 'communicate_utf8_async');

export class Monitor {
    constructor(settings, codeDir, notify) {
        this._settings = settings;
        this._codeDir = codeDir;
        this._notify = notify;
        this.now = Date.now();
        this.loaded = false;
        this.fetchFailed = false;
        this.lastUpdate = 0;
        this.liveStale = false;
        this.providers = [];
        this.costMonth = 0;
        this.costToday = 0;
        this.cost7d = 0;
        this.cost30d = 0;
        this.claudeMonth = 0;
        this.block = null;
        this.live = null;
        this.subscription = null;
        this.subscriptionOpenai = null;
        this.sessionModels = [];
        this.history = [];
        this.spark = [];
        this.projects = [];
        this.months = [];
        this.prevMonth = 0;
        this.models = [];
        this._proc = null;
    }

    get lang() {
        return this._settings.get_string('language') || L.systemLang(GLib.get_language_names());
    }

    get tr() {
        return L.translator(this.lang);
    }

    get hideValues() {
        return this._settings.get_boolean('privacy');
    }

    get budgetM() {
        return this._settings.get_int('budget-monthly');
    }

    get budgetPct() {
        return this.budgetM > 0 ? this.costMonth / this.budgetM * 100 : 0;
    }

    get projectedMonth() {
        return L.projectedMonth(this.costMonth, this.now);
    }

    get heroRange() {
        const r = this._settings.get_string('hero-range');
        return L.HERO_RANGES.includes(r) ? r : 'month';
    }

    cycleHeroRange() {
        const i = L.HERO_RANGES.indexOf(this.heroRange);
        this._settings.set_string('hero-range', L.HERO_RANGES[(i + 1) % L.HERO_RANGES.length]);
    }

    heroValue() {
        const r = this.heroRange;
        if (r === 'today') return this.costToday;
        if (r === 'd7') return this.cost7d;
        if (r === 'd30') return this.cost30d;
        return this.costMonth;
    }

    money(v) {
        return L.money(v, this.hideValues);
    }

    moneyCur(v, cur) {
        return L.moneyCur(v, cur, this.hideValues);
    }

    sessionModel() {
        return L.mainModel(this.sessionModels);
    }

    scopedModelLabel(name) {
        return L.scopedModelLabel(name, this.models, this.sessionModels, this.tr);
    }

    weeklyChecks(l) {
        return L.weeklyChecks(l, this.tr, n => this.scopedModelLabel(n));
    }

    timeToFull() {
        return L.timeToFull(this.live, this.block, this.now, this.liveStale);
    }

    weeklyPace(data) {
        return L.weeklyPace(data, this.live, this.now, this.liveStale);
    }

    resetLabel(iso) {
        return L.resetLabel(iso, this.now, this.lang);
    }

    timeLeft(iso) {
        return L.timeLeft(iso, this.now);
    }

    extraSubscriptions() {
        return L.extraSubscriptions(this._settings.get_string('extra-subscriptions'));
    }

    allSubscriptions() {
        const list = [];
        if (this.subscription) list.push(this.subscription);
        if (this.subscriptionOpenai) list.push(this.subscriptionOpenai);
        return list.concat(this.extraSubscriptions());
    }

    subsTotal() {
        return this.allSubscriptions().reduce((t, s) => t + s.price, 0);
    }

    get panelMode() {
        const m = this._settings.get_string('panel-display');
        return L.PANEL_MODES.includes(m) ? m : 'session';
    }

    cyclePanelMode(forward) {
        const i = L.PANEL_MODES.indexOf(this.panelMode);
        const n = L.PANEL_MODES.length;
        this._settings.set_string('panel-display', L.PANEL_MODES[(i + (forward ? 1 : n - 1)) % n]);
    }

    compactColor() {
        const mode = this.panelMode;
        if (!this.live) return null;
        if (mode === 'weekly') return L.sevColor(L.worstWeeklyPct(this.live));
        if (mode === 'session' || mode === 'reset') return L.sevColor(this.live.session.pct);
        return null;
    }

    compactText() {
        const mode = this.panelMode;
        const live = this.live;
        if (mode === 'today') return this.money(this.costToday);
        if (mode === 'weekly') return live ? 'w ' + L.worstWeeklyPct(live) + '%' : 'cc';
        if (mode === 'subs') {
            return this.hideValues ? '•••'
                : (this.subscription ? this.subscription.currency : 'US$') + this.subsTotal();
        }
        if (mode === 'reset') return live ? this.timeLeft(live.session.resets_at) : 'cc';
        return live ? live.session.pct + '%' : (this.block ? this.money(this.block.costUSD) : 'cc');
    }

    tooltip() {
        const tr = this.tr;
        if (!this.loaded) return tr('loading');
        return this.money(this.costMonth) + ' ' + tr('tipMonth')
            + (this.live ? ' · ' + tr('tipSession') + ' ' + this.live.session.pct + '%' : '')
            + (this.fetchFailed ? '\n' + tr('stale') : '');
    }

    async refresh() {
        this.now = Date.now();
        if (this._proc) return;
        const script = GLib.build_filenamev([this._codeDir, 'fetch.sh']);
        try {
            this._proc = Gio.Subprocess.new(
                ['timeout', '55', 'bash', script],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
            const [stdout] = await this._proc.communicate_utf8_async(null, null);
            this._ingest(JSON.parse(stdout));
        } catch (e) {
            this.fetchFailed = true;
        } finally {
            this._proc = null;
        }
    }

    cancel() {
        if (this._proc) this._proc.force_exit();
    }

    _ingest(j) {
        this.providers = j.providers || [];
        this.costMonth = j.totalMonth || 0;
        this.costToday = j.totalToday || 0;
        this.cost7d = j.total7d || 0;
        this.cost30d = j.total30d || 0;
        const claude = this.providers.find(p => p.id === 'claude');
        this.claudeMonth = claude ? claude.costMonth : 0;
        this.block = j.block || null;
        if (j.live) {
            const lv = L.normalizeLive(j.live);
            this._checkResets(this.live, lv);
            this.live = lv;
            this.liveStale = false;
        } else if (this.live) {
            this.liveStale = true;
        }
        this.subscription = j.subscription || null;
        this.subscriptionOpenai = j.subscriptionOpenai || null;
        this.sessionModels = j.sessionModels || [];
        this.history = j.history || [];
        this.spark = j.spark || [];
        this.projects = (j.projects || []).filter(p => p.cost > 0);
        let mh = j.months || [];
        if (claude) {
            const curM = L.currentMonthKey(this.now);
            if (mh.length > 0 && mh[mh.length - 1].m === curM) {
                mh[mh.length - 1].c = claude.costMonth;
            } else {
                mh.push({m: curM, c: claude.costMonth});
                if (mh.length > 6) mh = mh.slice(-6);
            }
        }
        this.months = mh;
        this.prevMonth = j.prevMonth || 0;
        this.models = (j.models || []).filter(m => m.cost > 0);
        this.loaded = true;
        this.lastUpdate = Date.now();
        this.fetchFailed = false;
        this._checkNotify();
        this._checkWeeklyNotify();
        this._checkPaceNotify();
        this._checkLocked();
        this._checkBudget();
    }

    _flags(key) {
        try {
            return JSON.parse(this._settings.get_string(key) || '{}');
        } catch (e) {
            return {};
        }
    }

    _checkResets(prev, cur) {
        if (!prev || !cur) return;
        const tr = this.tr;
        const thS = this._settings.get_int('notify-threshold');
        const thW = this._settings.get_int('notify-threshold-weekly');
        if (thS > 0 && prev.session && cur.session
            && prev.session.resets_at !== cur.session.resets_at && prev.session.pct >= thS)
            this._notifyReset('Claude ' + tr('session').toLowerCase(), cur.session);
        if (thW <= 0) return;
        const before = {};
        for (const c of this.weeklyChecks(prev)) before[c.key] = c.data;
        for (const c of this.weeklyChecks(cur)) {
            const old = before[c.key];
            if (old && old.resets_at !== c.data.resets_at && old.pct >= thW)
                this._notifyReset(c.label, c.data);
        }
    }

    _notifyReset(label, data) {
        const tr = this.tr;
        this._notify(label + ' · ' + tr('limitReset') + ' · ' + data.pct + '% · '
            + tr('resets') + ' ' + this.resetLabel(data.resets_at));
    }

    _checkNotify() {
        const th = this._settings.get_int('notify-threshold');
        if (th <= 0 || !this.live || this.liveStale) return;
        const s = this.live.session;
        const lv = L.notifyLevel(s.pct, th);
        if (lv === 0) return;
        if (!L.levelPending(this._settings.get_string('notified-session'), s.resets_at, lv)) return;
        this._settings.set_string('notified-session', L.levelKey(s.resets_at, lv));
        this._notify('Claude ' + s.pct + '% · ' + this.tr('resets') + ' ' + this.resetLabel(s.resets_at));
    }

    _checkWeeklyNotify() {
        const th = this._settings.get_int('notify-threshold-weekly');
        if (th <= 0 || !this.live || this.liveStale) return;
        const flags = this._flags('notified-weekly');
        let changed = false;
        for (const c of this.weeklyChecks(this.live)) {
            if (!c.data) continue;
            const lv = L.notifyLevel(c.data.pct, th);
            if (lv === 0 || !L.levelPending(flags[c.key], c.data.resets_at, lv)) continue;
            flags[c.key] = L.levelKey(c.data.resets_at, lv);
            changed = true;
            this._notify(c.label + ' ' + c.data.pct + '% · ' + this.tr('resets') + ' '
                + this.resetLabel(c.data.resets_at));
        }
        if (changed) this._settings.set_string('notified-weekly', JSON.stringify(flags));
    }

    _checkPaceNotify() {
        if (!this.live || this.liveStale) return;
        const tr = this.tr;
        const flags = this._flags('notified-pace');
        let changed = false;
        const thS = this._settings.get_int('notify-threshold');
        const eta = this.timeToFull();
        const s = this.live.session;
        if (thS > 0 && eta !== '' && s.pct < thS && flags.session !== String(s.resets_at)) {
            flags.session = String(s.resets_at);
            changed = true;
            this._notifyPace('Claude ' + tr('session').toLowerCase(), eta);
        }
        const thW = this._settings.get_int('notify-threshold-weekly');
        if (thW > 0) {
            for (const c of this.weeklyChecks(this.live)) {
                const p = this.weeklyPace(c.data);
                if (!p || !p.full || c.data.pct >= thW) continue;
                if (flags[c.key] === String(c.data.resets_at)) continue;
                flags[c.key] = String(c.data.resets_at);
                changed = true;
                this._notifyPace(c.label, p.full);
            }
        }
        if (changed) this._settings.set_string('notified-pace', JSON.stringify(flags));
    }

    _notifyPace(label, eta) {
        const tr = this.tr;
        this._notify(label + ' · ' + tr('pace') + ': ' + tr('limitFull') + ' ' + tr('inWord') + ' ' + eta);
    }

    _checkLocked() {
        if (!this.live || this.liveStale) return;
        const tr = this.tr;
        const flags = this._flags('notified-locked');
        let changed = false;
        const checks = [{key: 'session', data: this.live.session, label: 'Claude ' + tr('session').toLowerCase()}]
            .concat(this.weeklyChecks(this.live));
        for (const c of checks) {
            if (!c.data || !c.data.locked) continue;
            if (flags[c.key] === String(c.data.resets_at)) continue;
            flags[c.key] = String(c.data.resets_at);
            changed = true;
            this._notify(c.label + ' · ' + tr('locked') + ': ' + c.data.locked + ' · '
                + tr('resets') + ' ' + this.resetLabel(c.data.resets_at));
        }
        if (changed) this._settings.set_string('notified-locked', JSON.stringify(flags));
    }

    _checkBudget() {
        const b = this.budgetM;
        if (b <= 0 || !this.loaded) return;
        const pct = this.costMonth / b * 100;
        const level = pct >= 100 ? 100 : (pct >= 80 ? 80 : 0);
        if (level === 0) return;
        const month = L.currentMonthKey(this.now);
        const saved = (this._settings.get_string('notified-budget') || '').split(':');
        if (saved[0] === month && Number(saved[1] || 0) >= level) return;
        this._settings.set_string('notified-budget', month + ':' + level);
        this._notify(Math.round(pct) + '% ' + this.tr('budget') + ' · ' + this.money(this.costMonth) + ' / ' + this.money(b));
    }
}
