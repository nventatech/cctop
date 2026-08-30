// Checks the notification bookkeeping in main.qml: the reset time must
// identify a window despite the microseconds the API adds, and each window
// must notify once per level. The functions are pulled out of main.qml
// itself, so a change there is what the test sees.
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later
const assert = require("assert")
const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(path.join(__dirname, "../contents/ui/main.qml"), "utf8")
function grab(name) {
  const start = src.indexOf("function " + name + "(")
  assert.ok(start >= 0, name + " not found in main.qml")
  let i = src.indexOf("{", start), depth = 0
  for (let j = i; j < src.length; j++) {
    if (src[j] === "{") depth++
    else if (src[j] === "}" && --depth === 0) return src.slice(start, j + 1)
  }
  assert.fail("unbalanced braces in " + name)
}
eval(["roundReset", "notifyLevel", "levelKey", "levelPending"].map(grab).join("\n"))

// the same window, polled twice: microseconds differ and the second even
// crosses the minute, yet both must round to one key
const a = roundReset("2026-08-31T22:59:59.706811+00:00")
const b = roundReset("2026-08-31T23:00:00.365876+00:00")
assert.strictEqual(a, b, "jitter must collapse")
assert.strictEqual(a, "2026-08-31T23:00:00.000Z")
assert.notStrictEqual(roundReset("2026-09-07T23:00:00.1+00:00"), a, "a real reset must differ")
assert.strictEqual(roundReset("nonsense"), "nonsense", "unparseable value passes through")
assert.strictEqual(roundReset(null), null)

// levels: nothing below the threshold, then the threshold, 95 and 100
assert.strictEqual(notifyLevel(84, 85), 0)
assert.strictEqual(notifyLevel(85, 85), 85)
assert.strictEqual(notifyLevel(96, 85), 95)
assert.strictEqual(notifyLevel(100, 85), 100)
// a threshold above 95 must not fall back to a level below itself
assert.strictEqual(notifyLevel(96, 98), 0)
assert.strictEqual(notifyLevel(99, 98), 98)
assert.strictEqual(notifyLevel(100, 98), 100)

// one notification per level, escalating, and a new window starts over
const w1 = "2026-08-31T23:00:00.000Z", w2 = "2026-09-07T23:00:00.000Z"
assert.ok(levelPending("", w1, 85), "nothing notified yet")
const saved85 = levelKey(w1, 85)
assert.ok(!levelPending(saved85, w1, 85), "same level must not repeat")
assert.ok(levelPending(saved85, w1, 95), "a higher level still notifies")
assert.ok(!levelPending(levelKey(w1, 100), w1, 95), "no going back down")
assert.ok(levelPending(saved85, w2, 85), "the next window starts over")
// state written by 1.5.0 was the bare reset time: it notifies once, then settles
assert.ok(levelPending(w1, w1, 85), "state from the previous version notifies once")

console.log("ok   notification bookkeeping")
