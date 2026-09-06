// cctop - builds the popup content from the monitor state.
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import St from 'gi://St';

import * as L from './logic.js';
import * as W from './widgets.js';

const DARK = {
    bg: '#1a1a1d', surface: '#242427', surface2: '#2d2d31', border: '#34343a',
    text: '#eaeaee', muted: '#909299', accent: '#2a9fb8',
};
const OK = '#4ade80';
const WARN = '#fbbf24';
const ALERT = '#f2585f';

function toHex(c) {
    const h = v => Math.round(v * 255).toString(16).padStart(2, '0');
    return '#' + h(c.red / 255) + h(c.green / 255) + h(c.blue / 255);
}

function mix(bgHex, fgHex, a) {
    const bg = W.hexToRgb(bgHex), fg = W.hexToRgb(fgHex);
    const h = v => Math.round(v * 255).toString(16).padStart(2, '0');
    return '#' + [0, 1, 2].map(i => h(bg[i] * (1 - a) + fg[i] * a)).join('');
}

export function systemPalette(themeNode) {
    let text = '#eaeaee', bg = '#1a1a1d', accent = DARK.accent;
    try {
        text = toHex(themeNode.get_foreground_color());
        const [okBg, bgColor] = themeNode.lookup_color('-arrow-background-color', false);
        if (okBg) bg = toHex(bgColor);
        const [okAcc, acc] = themeNode.lookup_color('-st-accent-color', false);
        if (okAcc) accent = toHex(acc);
    } catch (e) {
    }
    return {
        bg, text, accent,
        surface: mix(bg, text, 0.05), surface2: mix(bg, text, 0.12),
        border: mix(bg, text, 0.18), muted: mix(bg, text, 0.55),
    };
}

export class Popup {
    constructor(monitor, extension, actions) {
        this._m = monitor;
        this._ext = extension;
        this._actions = actions;
        this.showHistory = false;
        this.showProjects = false;
        this.palette = DARK;
    }

    get dark() {
        return !this._ext.settings.get_boolean('follow-system-theme');
    }

    build() {
        const m = this._m, tr = m.tr, P = this.dark ? DARK : this.palette;
        this._P = P;
        const root = W.column([], 'cctop-root ' + (this.dark ? 'cctop-dark' : 'cctop-system'));
        if (this.dark) root.set_style('color: ' + P.text + ';');
        root.add_child(this._header());
        root.add_child(this._summary());
        if (this.showProjects && m.projects.length > 0) root.add_child(this._projects());
        root.add_child(this._session());
        if (this.showHistory && m.history.length > 0) root.add_child(this._history());
        if (this.showHistory && m.months.length > 1) root.add_child(this._months());
        if (m.live) root.add_child(this._weekly());
        const extra = m.live ? (m.live.extra || m.live.spend || null) : null;
        if (extra) root.add_child(this._extra(extra));
        if (m.allSubscriptions().length > 0) root.add_child(this._subs());
        root.add_child(this._footer());
        return root;
    }

    _muted(text, cls = 'cctop-micro') {
        return W.colored(text, this._P.muted, cls);
    }

    _text(text, cls = 'cctop-small') {
        return W.colored(text, this._P.text, cls);
    }

    _heading(text) {
        const l = W.colored(text, this._P.muted, 'cctop-heading');
        l.clutter_text.set_ellipsize(0);
        return l;
    }

    _header() {
        const m = this._m, P = this._P;
        const iconFile = Gio.File.new_for_path(this._ext.path + '/icons/cctop.svg');
        const icon = new St.Icon({gicon: new Gio.FileIcon({file: iconFile}), icon_size: 22, y_align: Clutter.ActorAlign.CENTER});
        const title = W.colored('cctop', P.text, 'cctop-title');
        const date = this._muted(L.longDate(new Date(m.now), m.lang));
        date.clutter_text.set_x_align(Clutter.ActorAlign.END);
        date.x_align = Clutter.ActorAlign.END;
        const eye = W.iconButton(m.hideValues ? 'view-conceal-symbolic' : 'view-reveal-symbolic',
            () => this._ext.settings.set_boolean('privacy', !m.hideValues));
        if (m.hideValues) eye.add_style_pseudo_class('checked');
        const proj = W.iconButton('folder-open-symbolic', () => {
            this.showProjects = !this.showProjects;
            this._actions.rerender();
        });
        if (this.showProjects) proj.add_style_pseudo_class('checked');
        const hist = W.iconButton('document-open-recent-symbolic', () => {
            this.showHistory = !this.showHistory;
            this._actions.rerender();
        });
        if (this.showHistory) hist.add_style_pseudo_class('checked');
        return W.row([icon, title, date, eye, proj, hist], 2);
    }

    _summary() {
        const m = this._m, tr = m.tr, P = this._P;
        const hero = W.colored(m.loaded ? m.money(m.heroValue()) : '…', P.text, 'cctop-hero');
        W.clickable(hero, () => m.cycleHeroRange());
        const rangeLabel = this._muted(tr(m.heroRange) + ' ▾', 'cctop-small');
        W.clickable(rangeLabel, () => m.cycleHeroRange());
        const line = [rangeLabel];
        line.push(this._muted(m.heroRange === 'month'
            ? '  ·  ' + tr('today') + ' ' + m.money(m.costToday)
            : '  ·  ' + tr('month') + ' ' + m.money(m.costMonth), 'cctop-small'));
        const delta = L.todayDelta(m.spark, m.costToday);
        if (m.heroRange === 'month' && delta !== null && !m.hideValues)
            line.push(W.colored(' (' + L.signedPct(delta) + ')', delta > 0 ? L.sevColor(100) : L.sevColor(0), 'cctop-small'));
        if (m.loaded && m.costMonth > 0) {
            const color = m.budgetM > 0 ? L.sevColor(m.projectedMonth / m.budgetM * 100) : P.muted;
            line.push(W.colored('  ·  ' + tr('projected') + ' ≈ ' + m.money(m.projectedMonth), color, 'cctop-small'));
        }
        const parts = [hero, W.row(line, -1, '')];

        if (m.loaded && m.prevMonth > 0) {
            const prev = [this._muted(tr('prevMonth') + ' ' + m.money(m.prevMonth), 'cctop-small')];
            if (m.costMonth > 0 && !m.hideValues) {
                const d = (m.projectedMonth - m.prevMonth) / m.prevMonth * 100;
                prev.push(W.colored('  ·  ≈ ' + L.signedPct(d), d > 0 ? L.sevColor(100) : L.sevColor(0), 'cctop-small'));
            }
            parts.push(W.row(prev, -1, ''));
        }

        if (m.budgetM > 0) {
            const bar = new W.ProgressBar(m.budgetPct, L.sevColor(m.budgetPct), P.surface2);
            bar.y_align = Clutter.ActorAlign.CENTER;
            const txt = this._muted(Math.round(m.budgetPct) + '% · ' + m.money(m.budgetM) + ' ' + tr('budget'));
            parts.push(W.spacer(2));
            parts.push(W.row([bar, txt], 0));
        }

        if (m.providers.length > 1) {
            const segs = m.providers.map(p => ({frac: m.costMonth > 0 ? p.costMonth / m.costMonth : 0, color: p.color}));
            parts.push(W.spacer(2));
            parts.push(new W.StackedBar(segs, P.surface2));
        }
        const legend = m.providers.map(p => W.row([
            W.dot(p.color),
            W.colored(p.name, P.text, 'cctop-micro'),
            this._muted(m.money(p.costMonth)),
        ], -1, 'cctop-row'));
        legend.forEach(l => (l.x_expand = false));
        parts.push(W.row(legend, -1, 'cctop-legend'));

        if (m.spark.length > 0) {
            parts.push(W.spacer(4));
            parts.push(this._sparkChart());
        }
        return W.column(parts);
    }

    _sparkChart() {
        const m = this._m, P = this._P;
        const days = m.spark.map(s => L.weekdayShort(new Date(s.d + 'T12:00:00'), m.lang));
        const tip = this._muted(' ');
        const chart = new W.BarChart(m.spark.map(s => s.c), P.accent, 42, i => {
            tip.text = i >= 0 ? days[i] + ' · ' + m.money(m.spark[i].c) : ' ';
        });
        const labels = new St.BoxLayout({x_expand: true, style_class: 'cctop-chart-labels'});
        for (const d of days) {
            const l = this._muted(d);
            l.x_expand = true;
            l.x_align = Clutter.ActorAlign.CENTER;
            labels.add_child(l);
        }
        return W.column([tip, chart, labels]);
    }

    _listRow(name, cost) {
        const m = this._m;
        const share = m.costMonth > 0 ? Math.round(cost / m.costMonth * 100) + '%' : '';
        return W.row([this._text(name), this._muted(share), this._muted(m.money(cost), 'cctop-small')], 0);
    }

    _projects() {
        const m = this._m, tr = m.tr;
        const items = [this._heading(tr('topProjects'))];
        for (const p of m.projects) items.push(this._listRow(p.name, p.cost));
        if (m.models.length > 0) {
            items.push(W.spacer(2));
            items.push(this._heading(tr('byModel')));
            for (const md of m.models) items.push(this._listRow(L.prettyModel(md.name), md.cost));
        }
        return W.card(items);
    }

    _session() {
        const m = this._m, tr = m.tr, P = this._P;
        const live = m.live;
        const pct = live ? live.session.pct : 0;
        const color = live ? L.sevColor(pct) : P.muted;
        const model = W.colored(m.sessionModel(), P.accent, 'cctop-micro cctop-bold');
        const head = W.row([this._heading(tr('session')), model, W.colored(live ? pct + '%' : '—', color, 'cctop-pct')], 1);
        const items = [head, new W.ProgressBar(pct, color, P.surface2)];
        const eta = m.timeToFull();
        if (eta !== '') {
            const l = W.colored(tr('pace') + ': ' + tr('limitFull') + ' ' + tr('inWord') + ' ' + eta, L.sevColor(100), 'cctop-micro');
            l.clutter_text.set_line_wrap(true);
            items.push(l);
        }
        if (live) {
            let t = tr('resets') + ' ' + L.hhmm(new Date(live.session.resets_at))
                + ' (' + tr('inWord') + ' ' + m.timeLeft(live.session.resets_at) + ')';
            if (m.block) t += '  ·  ' + m.money(m.block.costUSD) + ' ' + tr('thisWindow');
            if (m.liveStale) t += '  ·  offline';
            const l = this._muted(t);
            l.clutter_text.set_line_wrap(true);
            items.push(l);
            if (live.session.locked) {
                const lk = W.colored(tr('locked') + ': ' + live.session.locked, ALERT, 'cctop-micro');
                lk.clutter_text.set_line_wrap(true);
                items.push(lk);
            }
        } else if (m.loaded) {
            items.push(this._muted(tr('noSession')));
        }
        return W.card(items);
    }

    _history() {
        const m = this._m, tr = m.tr, P = this._P;
        const items = [this._heading(tr('hist'))];
        for (const h of m.history) {
            items.push(W.row([
                this._muted(L.dayMonthTime(new Date(h.last), m.lang)),
                W.colored(L.mainModel(h.models), P.accent, 'cctop-micro cctop-bold'),
                W.colored(m.money(h.cost), P.text, 'cctop-micro'),
            ], 1));
        }
        return W.card(items);
    }

    _months() {
        const m = this._m, tr = m.tr, P = this._P;
        const top = new St.BoxLayout({x_expand: true, style_class: 'cctop-chart-labels'});
        const bottom = new St.BoxLayout({x_expand: true, style_class: 'cctop-chart-labels'});
        for (const mo of m.months) {
            const v = this._muted(m.money(mo.c));
            v.x_expand = true;
            v.x_align = Clutter.ActorAlign.CENTER;
            top.add_child(v);
            const n = this._muted(L.monthShort(new Date(mo.m + '-15T12:00:00'), m.lang));
            n.x_expand = true;
            n.x_align = Clutter.ActorAlign.CENTER;
            bottom.add_child(n);
        }
        const chart = new W.BarChart(m.months.map(mo => mo.c), P.accent, 52, null);
        return W.card([this._heading(tr('months6')), top, chart, bottom]);
    }

    _weekly() {
        const m = this._m, tr = m.tr;
        const list = m.live.weekly ? [{label: tr('weeklyAll'), data: m.live.weekly}] : [];
        for (const w of m.live.weekly_models || [])
            list.push({label: m.scopedModelLabel(w.model).toUpperCase(), data: w});
        const grid = new St.BoxLayout({vertical: true, x_expand: true, style_class: 'cctop-grid'});
        for (let i = 0; i < list.length; i += 2) {
            const wide = i === list.length - 1;
            const line = new St.BoxLayout({x_expand: true, style_class: 'cctop-grid'});
            line.add_child(this._weeklyCard(list[i], wide));
            if (!wide) line.add_child(this._weeklyCard(list[i + 1], false));
            grid.add_child(line);
        }
        return grid;
    }

    _weeklyCard(item, wide) {
        const m = this._m, tr = m.tr, P = this._P;
        const d = item.data;
        const color = L.sevColor(d.pct);
        const head = W.row([this._heading(item.label), W.colored(d.pct + '%', color, 'cctop-small cctop-bold')], 0);
        const reset = this._muted((wide ? tr('resets') + ' ' : '') + L.weekdayTime(d.resets_at, m.lang));
        const foot = [reset];
        const pace = m.weeklyPace(d);
        if (pace) {
            const t = pace.full ? '100% ' + tr('inWord') + ' ' + pace.full : '≈' + pace.atReset + '% ' + tr('atReset');
            foot.push(W.colored(t, pace.full ? WARN : P.muted, 'cctop-micro'));
        }
        const items = [head, new W.ProgressBar(d.pct, color, P.surface2), W.row(foot, 0)];
        if (d.locked) {
            const lk = W.colored(tr('locked') + ': ' + d.locked, ALERT, 'cctop-micro');
            lk.clutter_text.set_line_wrap(true);
            items.push(lk);
        }
        const c = W.card(items, d.active ? color : null);
        c.x_expand = true;
        return c;
    }

    _extra(extra) {
        const m = this._m, tr = m.tr, P = this._P;
        const pct = extra.pct || 0;
        const head = W.row([this._heading(tr('extra')), W.colored(Math.round(pct) + '%', L.sevColor(pct), 'cctop-small cctop-bold')], 0);
        const txt = m.moneyCur(extra.used || 0, extra.currency)
            + (extra.limit ? ' / ' + m.moneyCur(extra.limit, extra.currency) : '') + ' ' + tr('credits');
        return W.card([head, new W.ProgressBar(pct, L.sevColor(pct), P.surface2), this._muted(txt)]);
    }

    _subs() {
        const m = this._m, tr = m.tr, P = this._P;
        const items = [this._heading(tr('subs'))];
        for (const s of m.allSubscriptions()) {
            const price = (m.hideValues ? s.currency + '•••' : s.currency + s.price) + tr('perMonth');
            items.push(W.row([this._text(s.name), this._muted(price, 'cctop-small')], 0));
        }
        items.push(W.separator());
        const total = (m.subscription ? m.subscription.currency : 'US$') + (m.hideValues ? '•••' : m.subsTotal()) + tr('perMonth');
        items.push(W.row([this._text(tr('subsTotal'), 'cctop-small cctop-bold'), W.colored(total, P.accent, 'cctop-small cctop-bold')], 0));
        if (m.subscription && m.claudeMonth > 0 && m.subscription.price > 0) {
            const ratio = m.hideValues ? '•••' : (m.claudeMonth / m.subscription.price).toFixed(1);
            items.push(this._muted(tr('apiEq') + ' ' + m.money(m.claudeMonth) + '  ·  ' + ratio + 'x ' + tr('planValue')));
        }
        return W.card(items);
    }

    _footer() {
        const m = this._m, tr = m.tr, P = this._P;
        const donate = W.iconButton('emblem-favorite-symbolic', () => this._actions.openUrl(L.DONATE_URL));
        const status = W.colored(m.fetchFailed ? tr('stale') : L.updatedText(m.lastUpdate, m.now, tr),
            m.fetchFailed ? WARN : P.muted, 'cctop-micro');
        const exp = W.iconButton('document-save-symbolic', () => this._actions.exportCsv(), tr('exportCsv'));
        const refresh = W.iconButton('view-refresh-symbolic', () => this._actions.refresh());
        const prefs = W.iconButton('preferences-system-symbolic', () => this._actions.openPrefs());
        return W.row([donate, status, exp, refresh, prefs], 1);
    }
}
