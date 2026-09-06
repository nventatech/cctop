// Checks the notification bookkeeping of the GNOME extension: the reset time
// must identify a window despite the microseconds the API adds, and each
// window must notify once per level. Same cases as notify.js, run against
// gnome/lib/logic.js.
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later
import assert from 'node:assert';
import * as L from '../gnome/lib/logic.js';

const a = L.roundReset('2026-08-31T22:59:59.706811+00:00');
const b = L.roundReset('2026-08-31T23:00:00.365876+00:00');
assert.strictEqual(a, b, 'jitter must collapse');
assert.strictEqual(a, '2026-08-31T23:00:00.000Z');
assert.notStrictEqual(L.roundReset('2026-09-07T23:00:00.1+00:00'), a, 'a real reset must differ');
assert.strictEqual(L.roundReset('nonsense'), 'nonsense', 'unparseable value passes through');

assert.strictEqual(L.notifyLevel(84, 85), 0);
assert.strictEqual(L.notifyLevel(85, 85), 85);
assert.strictEqual(L.notifyLevel(96, 85), 95);
assert.strictEqual(L.notifyLevel(100, 85), 100);
assert.strictEqual(L.notifyLevel(97, 96), 96, 'threshold above 95 skips the 95 step');

let saved = '';
assert.ok(L.levelPending(saved, a, 85), 'first level notifies');
saved = L.levelKey(a, 85);
assert.ok(!L.levelPending(saved, a, 85), 'same level does not repeat');
assert.ok(L.levelPending(saved, a, 95), 'next level notifies');
saved = L.levelKey(a, 95);
assert.ok(!L.levelPending(saved, a, 85), 'lower level never comes back');
assert.ok(L.levelPending(saved, L.roundReset('2026-09-07T23:00:00+00:00'), 85), 'new window starts over');
assert.ok(L.levelPending(a, a, 85), 'legacy value without level notifies once');

const now = Date.parse('2026-09-05T20:00:00Z');
assert.strictEqual(L.money(12.345, false), '$12.35');
assert.strictEqual(L.money(123.4, false), '$123');
assert.strictEqual(L.money(5, true), '$•••');
assert.strictEqual(L.prettyModel('claude-opus-4-1-20250805'), 'Opus 4.1');
assert.strictEqual(L.mainModel(['claude-haiku-4-5', 'claude-sonnet-4-5']), 'Sonnet 4.5');
assert.strictEqual(L.timeLeft('2026-09-05T23:30:00Z', now), '3h 30m');
assert.deepStrictEqual(L.weeklyPace({pct: 60, resets_at: '2026-09-08T10:00:00Z'}, {}, now, false), {atReset: 95});
assert.strictEqual(L.weeklyPace({pct: 60, resets_at: '2026-09-08T10:00:00Z'}, {}, now, true), null, 'stale live skips pace');
assert.deepStrictEqual(L.extraSubscriptions('Cursor Pro: 20\nfoo\nX : 9.5'),
    [{name: 'Cursor Pro', price: 20, currency: 'US$'}, {name: 'X', price: 9.5, currency: 'US$'}]);
assert.strictEqual(L.currentMonthKey(now), '2026-09');
assert.strictEqual(L.systemLang(['pt_BR.UTF-8']), 'pt_BR');
assert.strictEqual(L.systemLang(['C']), 'en');

console.log('ok   gnome logic helpers');
