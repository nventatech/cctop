// cctop - pure helpers shared by the panel, the popup and the notifications.
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later

import {dict, locales} from './strings.js';

export const HERO_RANGES = ['month', 'today', 'd7', 'd30'];
export const PANEL_MODES = ['session', 'weekly', 'today', 'subs', 'reset'];
export const DONATE_URL = 'https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD';

export function systemLang(names) {
    const n = (names && names[0]) || '';
    if (n.startsWith('pt')) return 'pt_BR';
    if (n.startsWith('es')) return 'es';
    return 'en';
}

export function translator(lang) {
    const table = dict[lang] || dict.en;
    return key => table[key];
}

export function localeOf(lang) {
    return locales[lang] || 'en-US';
}

export function money(v, hide) {
    if (hide) return '$•••';
    return '$' + Number(v || 0).toFixed(v >= 100 ? 0 : 2);
}

export function moneyCur(v, cur, hide) {
    if (!cur || cur === 'USD' || cur === 'US$') return money(v, hide);
    return cur + ' ' + (hide ? '•••' : Number(v || 0).toFixed(v >= 100 ? 0 : 2));
}

function hslToHex(h, s, l) {
    const k = n => (n + h * 12) % 12;
    const a = s * Math.min(l, 1 - l);
    const f = n => {
        const c = l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
        return Math.round(c * 255).toString(16).padStart(2, '0');
    };
    return '#' + f(0) + f(8) + f(4);
}

export function sevColor(pct) {
    const t = Math.max(0, Math.min(1, (pct || 0) / 100));
    return hslToHex((1 - t) * 0.33, 0.72, 0.58);
}

export function prettyModel(m) {
    const p = String(m).replace('claude-', '').split('-');
    if (p.length && /^\d{8}$/.test(p[p.length - 1])) p.pop();
    return p.map(s => s.charAt(0).toUpperCase() + s.slice(1))
        .join(' ').replace(/(\d) (\d)/, '$1.$2');
}

export function mainModel(list) {
    list = list || [];
    const main = list.filter(m => m.indexOf('haiku') < 0);
    const pick = main.length ? main : list;
    return pick.length ? prettyModel(pick[pick.length - 1]) : '';
}

export function scopedModelLabel(name, models, sessionModels, tr) {
    if (!name) return mainModel(sessionModels) || tr('weeklyModel');
    const seen = (models || []).map(m => m.name).concat(sessionModels || []);
    for (let i = seen.length - 1; i >= 0; i--)
        if (seen[i].toLowerCase().indexOf(name.toLowerCase()) >= 0) return prettyModel(seen[i]);
    return name;
}

export function worstWeeklyPct(live) {
    if (!live) return 0;
    let pct = live.weekly ? live.weekly.pct : 0;
    for (const w of live.weekly_models || []) pct = Math.max(pct, w.pct);
    return pct;
}

export function timeLeft(iso, now) {
    const mins = Math.max(0, Math.round((new Date(iso).getTime() - now) / 60000));
    const h = Math.floor(mins / 60), m = mins % 60;
    return h > 0 ? h + 'h ' + m + 'm' : m + 'm';
}

export function timeToFull(live, block, now, liveStale) {
    if (!live || !block || liveStale) return '';
    const start = new Date(block.startTime).getTime();
    const end = new Date(live.session.resets_at).getTime();
    const pct = live.session.pct;
    if (isNaN(start) || isNaN(end) || pct <= 0 || now <= start) return '';
    const elapsed = now - start;
    if (elapsed < (end - start) * 0.2) return '';
    const eta = elapsed * (100 - pct) / pct;
    if (eta <= 0 || now + eta >= end) return '';
    return timeLeft(new Date(now + eta).toISOString(), now);
}

export function weeklyPace(data, live, now, liveStale) {
    if (!data || !live || liveStale) return null;
    const end = new Date(data.resets_at).getTime();
    const start = end - 7 * 24 * 3600 * 1000;
    const pct = data.pct;
    if (isNaN(end) || pct <= 0 || now <= start || now >= end) return null;
    const elapsed = now - start;
    if (elapsed < (end - start) * 0.2) return null;
    const eta = elapsed * (100 - pct) / pct;
    if (now + eta >= end) return {atReset: Math.round(pct * (end - start) / elapsed)};
    const hours = Math.floor(eta / 3600000);
    const t = hours >= 24 ? Math.floor(hours / 24) + 'd ' + (hours % 24) + 'h'
        : timeLeft(new Date(now + eta).toISOString(), now);
    return {full: t};
}

export function roundReset(s) {
    const t = Date.parse(s);
    return isNaN(t) ? s : new Date(Math.round(t / 60000) * 60000).toISOString();
}

export function normalizeLive(l) {
    const w = [l.session, l.weekly].concat(l.weekly_models || []);
    for (const item of w)
        if (item && item.resets_at) item.resets_at = roundReset(item.resets_at);
    return l;
}

export function weeklyChecks(l, tr, scopedLabel) {
    const out = l && l.weekly ? [{key: 'all', data: l.weekly, label: tr('weeklyAll')}] : [];
    const wm = (l && l.weekly_models) || [];
    wm.forEach((w, i) => out.push({
        key: w.model || ('scoped' + i), data: w,
        label: scopedLabel(w.model).toUpperCase(),
    }));
    return out;
}

function pad2(n) {
    return String(n).padStart(2, '0');
}

export function hhmm(d) {
    return pad2(d.getHours()) + ':' + pad2(d.getMinutes());
}

export function weekdayShort(d, lang) {
    return new Intl.DateTimeFormat(localeOf(lang), {weekday: 'short'}).format(d).replace('.', '').slice(0, 3);
}

export function monthShort(d, lang) {
    return new Intl.DateTimeFormat(localeOf(lang), {month: 'short'}).format(d).replace('.', '').slice(0, 3);
}

export function longDate(d, lang) {
    return new Intl.DateTimeFormat(localeOf(lang), {weekday: 'long', day: 'numeric', month: 'long'}).format(d);
}

export function dayMonthTime(d, lang) {
    return d.getDate() + ' ' + monthShort(d, lang) + ' ' + hhmm(d);
}

export function weekdayTime(iso, lang) {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return weekdayShort(d, lang) + ' ' + hhmm(d);
}

export function resetLabel(iso, now, lang) {
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.getTime() - now < 24 * 3600 * 1000 ? hhmm(d) : weekdayTime(iso, lang);
}

export function updatedText(lastUpdate, now, tr) {
    if (!lastUpdate) return '';
    const mins = Math.max(0, Math.round((now - lastUpdate) / 60000));
    if (mins === 0) return tr('justNow');
    const h = Math.floor(mins / 60), m = mins % 60;
    const t = h > 0 ? h + 'h ' + (m < 10 ? '0' : '') + m + 'm' : m + 'm';
    return tr('updated') + ' ' + t + (tr('agoSuffix') ? ' ' + tr('agoSuffix') : '');
}

export function extraSubscriptions(text) {
    const list = [];
    for (const line of String(text || '').split('\n')) {
        const m = line.match(/^\s*(.+?)\s*:\s*(\d+(?:\.\d+)?)\s*$/);
        if (m) list.push({name: m[1], price: Number(m[2]), currency: 'US$'});
    }
    return list;
}

export function notifyLevel(pct, th) {
    let lv = 0;
    for (const step of [th, 95, 100])
        if (step >= th && pct >= step && step > lv) lv = step;
    return lv;
}

export function levelKey(resetsAt, lv) {
    return String(resetsAt || '') + '|' + lv;
}

export function levelPending(saved, resetsAt, lv) {
    const p = String(saved || '').split('|');
    return !(p[0] === String(resetsAt || '') && Number(p[1]) >= lv);
}

export function projectedMonth(costMonth, now) {
    const d = new Date(now);
    const daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    return costMonth / d.getDate() * daysInMonth;
}

export function currentMonthKey(now) {
    const d = new Date(now);
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1);
}

export function todayDelta(spark, costToday) {
    if (!spark || spark.length < 2) return null;
    const y = spark[spark.length - 2].c;
    if (!(y > 0)) return null;
    return (costToday - y) / y * 100;
}

export function signedPct(delta) {
    return (delta >= 0 ? '+' : '−') + Math.abs(Math.round(delta || 0)) + '%';
}
