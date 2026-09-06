// cctop - small St building blocks: labels, rows, cards, bars and charts.
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later

import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import St from 'gi://St';

export function hexToRgb(hex) {
    const h = hex.replace('#', '');
    return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16) / 255);
}

function setSource(cr, color, alpha = 1) {
    const [r, g, b] = hexToRgb(color);
    cr.setSourceRGBA(r, g, b, alpha);
}

function roundedRect(cr, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    cr.newSubPath();
    cr.arc(x + w - r, y + r, r, -Math.PI / 2, 0);
    cr.arc(x + w - r, y + h - r, r, 0, Math.PI / 2);
    cr.arc(x + r, y + h - r, r, Math.PI / 2, Math.PI);
    cr.arc(x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
    cr.closePath();
}

export function label(text, classes = '', style = '') {
    const l = new St.Label({text: String(text), y_align: Clutter.ActorAlign.CENTER});
    if (classes) for (const c of classes.split(' ')) if (c) l.add_style_class_name(c);
    if (style) l.set_style(style);
    l.clutter_text.set_ellipsize(3);
    return l;
}

export function colored(text, color, classes = '') {
    return label(text, classes, 'color: ' + color + ';');
}

export function row(children = [], expandIndex = -1, classes = 'cctop-row') {
    const r = new St.BoxLayout({x_expand: true});
    for (const c of classes.split(' ')) if (c) r.add_style_class_name(c);
    children.forEach((c, i) => {
        if (i === expandIndex) c.x_expand = true;
        r.add_child(c);
    });
    return r;
}

export function column(children = [], classes = '') {
    const c = new St.BoxLayout({vertical: true, x_expand: true});
    for (const k of classes.split(' ')) if (k) c.add_style_class_name(k);
    for (const ch of children) c.add_child(ch);
    return c;
}

export function card(children = [], borderColor = null) {
    const c = column(children, 'cctop-card');
    if (borderColor) {
        c.add_style_class_name('cctop-card-active');
        c.set_style('border-color: ' + borderColor + ';');
    }
    return c;
}

export function spacer(px) {
    return new St.Widget({height: px});
}

export function separator() {
    return new St.Widget({x_expand: true, style_class: 'cctop-separator'});
}

export function dot(color, cls = 'cctop-legend-dot') {
    return new St.Widget({style_class: cls, y_align: Clutter.ActorAlign.CENTER, style: 'background-color: ' + color + ';'});
}

export function iconButton(iconName, onClick, tooltip = '') {
    const b = new St.Button({style_class: 'cctop-btn', can_focus: true, reactive: true, track_hover: true});
    b.set_child(new St.Icon({icon_name: iconName}));
    b.connect('clicked', () => onClick());
    if (tooltip) b.accessible_name = tooltip;
    return b;
}

export function clickable(actor, onClick) {
    actor.reactive = true;
    actor.connect('button-press-event', () => {
        onClick();
        return Clutter.EVENT_STOP;
    });
    return actor;
}

export const ProgressBar = GObject.registerClass(
class CctopProgressBar extends St.DrawingArea {
    _init(pct, color, track) {
        super._init({x_expand: true, height: 6});
        this._pct = Math.max(0, Math.min(1, (pct || 0) / 100));
        this._color = color;
        this._track = track;
        this.connect('repaint', () => this._draw());
    }

    _draw() {
        const cr = this.get_context();
        const [w, h] = this.get_surface_size();
        setSource(cr, this._track);
        roundedRect(cr, 0, 0, w, h, 3);
        cr.fill();
        if (this._pct > 0) {
            setSource(cr, this._color);
            roundedRect(cr, 0, 0, Math.max(h, w * this._pct), h, 3);
            cr.fill();
        }
        cr.$dispose();
    }
});

export const StackedBar = GObject.registerClass(
class CctopStackedBar extends St.DrawingArea {
    _init(segments, track) {
        super._init({x_expand: true, height: 6});
        this._segments = segments;
        this._track = track;
        this.connect('repaint', () => this._draw());
    }

    _draw() {
        const cr = this.get_context();
        const [w, h] = this.get_surface_size();
        roundedRect(cr, 0, 0, w, h, 3);
        cr.clip();
        setSource(cr, this._track);
        cr.rectangle(0, 0, w, h);
        cr.fill();
        let x = 0;
        for (const s of this._segments) {
            const sw = w * s.frac;
            setSource(cr, s.color);
            cr.rectangle(x, 0, sw, h);
            cr.fill();
            x += sw;
        }
        cr.$dispose();
    }
});

export const BarChart = GObject.registerClass(
class CctopBarChart extends St.DrawingArea {
    _init(values, color, height, onHover) {
        super._init({x_expand: true, height, reactive: true, track_hover: true});
        this._values = values;
        this._color = color;
        this._hover = -1;
        this._onHover = onHover;
        this.connect('repaint', () => this._draw());
        this.connect('motion-event', (_a, event) => {
            const [x] = event.get_coords();
            const [ax] = this.get_transformed_position();
            this._setHover(this._indexAt(x - ax));
            return Clutter.EVENT_PROPAGATE;
        });
        this.connect('leave-event', () => {
            this._setHover(-1);
            return Clutter.EVENT_PROPAGATE;
        });
    }

    _slot() {
        const [w] = this.get_surface_size();
        const n = this._values.length;
        const gap = 4;
        return {n, gap, bw: (w - gap * (n - 1)) / n};
    }

    _indexAt(x) {
        const {n, gap, bw} = this._slot();
        const i = Math.floor(x / (bw + gap));
        return i >= 0 && i < n ? i : -1;
    }

    _setHover(i) {
        if (i === this._hover) return;
        this._hover = i;
        this.queue_repaint();
        if (this._onHover) this._onHover(i);
    }

    _draw() {
        const cr = this.get_context();
        const [, h] = this.get_surface_size();
        const {n, gap, bw} = this._slot();
        const peak = Math.max(...this._values, 0.01);
        for (let i = 0; i < n; i++) {
            const bh = Math.max(3, h * (this._values[i] / peak));
            const full = i === n - 1 || i === this._hover;
            setSource(cr, this._color, full ? 1 : 0.5);
            roundedRect(cr, i * (bw + gap), h - bh, bw, bh, 2);
            cr.fill();
        }
        cr.$dispose();
    }
});
