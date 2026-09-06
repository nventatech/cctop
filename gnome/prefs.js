// cctop - settings page (language, panel display, notifications, donate).
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later

import Adw from 'gi://Adw';
import Gdk from 'gi://Gdk';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const DONATE_URL = 'https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD';

const LANGUAGES = [['', 'System'], ['en', 'English'], ['pt_BR', 'Português (Brasil)'], ['es', 'Español']];
const PANEL = [['session', 'Session %'], ['weekly', 'Weekly % (tightest limit)'], ['today', 'Spend today'],
    ['subs', 'Subscriptions total'], ['reset', 'Session reset countdown']];

function comboRow(settings, key, title, options) {
    const list = new Gtk.StringList();
    for (const [, text] of options) list.append(text);
    const row = new Adw.ComboRow({title, model: list});
    const idx = options.findIndex(o => o[0] === settings.get_string(key));
    row.selected = idx >= 0 ? idx : 0;
    row.connect('notify::selected', () => settings.set_string(key, options[row.selected][0]));
    return row;
}

function spinRow(settings, key, title, lower, upper, step) {
    const row = new Adw.SpinRow({
        title,
        adjustment: new Gtk.Adjustment({lower, upper, step_increment: step, page_increment: step * 2}),
    });
    row.value = settings.get_int(key);
    row.connect('notify::value', () => settings.set_int(key, Math.round(row.value)));
    return row;
}

export default class CctopPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage();

        const general = new Adw.PreferencesGroup({title: 'General'});
        general.add(comboRow(settings, 'language', 'Language', LANGUAGES));
        general.add(comboRow(settings, 'panel-display', 'Panel shows', PANEL));
        general.add(spinRow(settings, 'refresh-interval', 'Refresh every (seconds)', 30, 3600, 30));
        const theme = new Adw.SwitchRow({title: 'Popup colors', subtitle: 'Follow the system theme'});
        settings.bind('follow-system-theme', theme, 'active', Gio.SettingsBindFlags.DEFAULT);
        general.add(theme);
        page.add(general);

        const notify = new Adw.PreferencesGroup({title: 'Notifications'});
        notify.add(spinRow(settings, 'notify-threshold', 'Notify at session % (0 = off)', 0, 100, 5));
        notify.add(spinRow(settings, 'notify-threshold-weekly', 'Notify at weekly % (0 = off)', 0, 100, 5));
        notify.add(spinRow(settings, 'budget-monthly', 'Monthly budget in US$ (0 = off)', 0, 100000, 10));
        page.add(notify);

        const subs = new Adw.PreferencesGroup({title: 'Extra subscriptions', description: 'One per line, e.g. Cursor Pro: 20'});
        const view = new Gtk.TextView({
            wrap_mode: Gtk.WrapMode.WORD, top_margin: 8, bottom_margin: 8, left_margin: 10, right_margin: 10,
            height_request: 90,
        });
        view.buffer.text = settings.get_string('extra-subscriptions');
        view.buffer.connect('changed', () => settings.set_string('extra-subscriptions', view.buffer.text));
        const frame = new Gtk.Frame({child: view});
        frame.add_css_class('view');
        subs.add(frame);
        page.add(subs);

        const donate = new Adw.PreferencesGroup({title: 'Enjoying cctop?'});
        const donateRow = new Adw.ActionRow({title: 'Donate via PayPal', activatable: true});
        donateRow.add_suffix(new Gtk.Image({icon_name: 'emblem-favorite-symbolic'}));
        donateRow.connect('activated', () => Gtk.show_uri(window, DONATE_URL, Gdk.CURRENT_TIME));
        donate.add(donateRow);
        const qr = Gtk.Picture.new_for_filename(this.path + '/images/donate-qr.png');
        qr.set_size_request(140, 140);
        qr.content_fit = Gtk.ContentFit.CONTAIN;
        qr.halign = Gtk.Align.START;
        qr.margin_top = 8;
        donate.add(qr);
        page.add(donate);

        window.add(page);
    }
}
