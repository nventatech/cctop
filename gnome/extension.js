// cctop - AI usage/cost monitor for the GNOME Shell top bar.
// Panel shows the live Claude session usage; the popup shows the monthly
// cost per provider, live session/weekly limits and subscriptions.
// All data is read locally (no accounts, no API keys).
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {Monitor} from './lib/data.js';
import {Popup, systemPalette} from './lib/popup.js';

const RENDER_KEYS = ['privacy', 'panel-display', 'hero-range', 'language',
    'follow-system-theme', 'extra-subscriptions', 'budget-monthly'];

const Indicator = GObject.registerClass(
class CctopIndicator extends PanelMenu.Button {
    _init(extension, monitor) {
        super._init(0.5, 'cctop', false);
        this._ext = extension;
        this._m = monitor;
        this._popup = new Popup(monitor, extension, {
            rerender: () => this.render(),
            refresh: () => this._ext.refreshNow(),
            exportCsv: () => this._ext.runScript('export.sh'),
            openPrefs: () => {
                this.menu.close();
                this._ext.openPreferences();
            },
            openUrl: url => Gio.AppInfo.launch_default_for_uri(url, null),
        });

        const box = new St.BoxLayout({y_align: Clutter.ActorAlign.CENTER});
        this._dot = new St.Widget({style_class: 'cctop-panel-dot', y_align: Clutter.ActorAlign.CENTER});
        this._label = new St.Label({style_class: 'cctop-panel-label', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._dot);
        box.add_child(this._label);
        this.add_child(box);

        this.connect('scroll-event', (_a, event) => {
            const dir = event.get_scroll_direction();
            if (dir === Clutter.ScrollDirection.DOWN) this._m.cyclePanelMode(true);
            else if (dir === Clutter.ScrollDirection.UP) this._m.cyclePanelMode(false);
            else return Clutter.EVENT_PROPAGATE;
            return Clutter.EVENT_STOP;
        });

        this._content = null;
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open) {
                this._m.now = Date.now();
                this.render();
            }
        });
    }

    render() {
        const m = this._m;
        const color = m.compactColor();
        this._dot.visible = m.live !== null;
        this._dot.set_style(color ? 'background-color: ' + color + ';' : '');
        this._label.text = m.compactText();
        this._label.set_style(color ? 'color: ' + color + ';' : '');
        this.accessible_name = m.tooltip();

        const dark = this._popup.dark;
        if (dark) this.menu.actor.add_style_class_name('cctop-boxpointer');
        else this.menu.actor.remove_style_class_name('cctop-boxpointer');
        if (!dark) this._popup.palette = systemPalette(this.menu.actor.get_theme_node());

        if (this._content) this._content.destroy();
        this._content = this._popup.build();
        this.menu.box.add_child(this._content);
    }
});

export default class CctopExtension extends Extension {
    enable() {
        this.settings = this.getSettings();
        this._codeDir = GLib.build_filenamev([this.path, 'code']);
        this._monitor = new Monitor(this.settings, this._codeDir, msg => Main.notify('cctop', msg));
        this._indicator = new Indicator(this, this._monitor);
        Main.panel.addToStatusArea(this.uuid, this._indicator);
        this._indicator.render();

        this._settingsIds = RENDER_KEYS.map(k => this.settings.connect('changed::' + k, () => this._indicator.render()));
        this._settingsIds.push(this.settings.connect('changed::refresh-interval', () => this._startTimer()));
        this._startTimer();
        this.refreshNow();
    }

    disable() {
        this._stopTimer();
        if (this._settingsIds) for (const id of this._settingsIds) this.settings.disconnect(id);
        this._settingsIds = null;
        if (this._monitor) this._monitor.cancel();
        this._monitor = null;
        if (this._indicator) this._indicator.destroy();
        this._indicator = null;
        this.settings = null;
    }

    _startTimer() {
        this._stopTimer();
        const secs = Math.max(30, this.settings.get_int('refresh-interval'));
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, secs, () => {
            this.refreshNow();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stopTimer() {
        if (this._timer) GLib.Source.remove(this._timer);
        this._timer = null;
    }

    refreshNow() {
        if (!this._monitor) return;
        this._monitor.refresh().then(() => {
            if (this._indicator) this._indicator.render();
        }).catch(e => console.error('cctop: ' + e));
    }

    runScript(name) {
        try {
            Gio.Subprocess.new(['bash', GLib.build_filenamev([this._codeDir, name])], Gio.SubprocessFlags.NONE);
        } catch (e) {
            console.error('cctop: ' + e);
        }
    }
}
