let kit = TestKit.make()

// make seeds one entry.
let h = RewindHistory.make(~cap=3, "a")
TestKit.check(kit, "make: length is 1", RewindHistory.length(h) == 1)
TestKit.check(kit, "make: last is the initial value", RewindHistory.last(h) == "a")
TestKit.check(kit, "make: get(0) is the initial value", RewindHistory.get(h, 0) == Some("a"))
TestKit.check(kit, "make: dropped is 0", RewindHistory.dropped(h) == 0)
TestKit.check(kit, "make: cap is what was passed in", RewindHistory.cap(h) == 3)
TestKit.check(kit, "make: toArray is [a]", RewindHistory.toArray(h) == ["a"])

// push below cap grows the history and keeps order oldest-first.
let h = RewindHistory.push(h, "b")
TestKit.check(kit, "push below cap: length is 2", RewindHistory.length(h) == 2)
TestKit.check(kit, "push below cap: last is the new value", RewindHistory.last(h) == "b")
TestKit.check(kit, "push below cap: toArray is oldest-first", RewindHistory.toArray(h) == ["a", "b"])
TestKit.check(kit, "push below cap: dropped stays 0", RewindHistory.dropped(h) == 0)

// push at cap drops the oldest entry and counts it as dropped.
let h = RewindHistory.push(h, "c")
TestKit.check(kit, "push at cap: length stays at cap", RewindHistory.length(h) == 3)
let h = RewindHistory.push(h, "d")
TestKit.check(kit, "push over cap: length stays at cap", RewindHistory.length(h) == 3)
TestKit.check(kit, "push over cap: drops the oldest", RewindHistory.toArray(h) == ["b", "c", "d"])
TestKit.check(kit, "push over cap: dropped is 1", RewindHistory.dropped(h) == 1)
TestKit.check(kit, "push over cap: last is the newest", RewindHistory.last(h) == "d")

// pushing twice past cap in one go drops two.
let h = RewindHistory.push(h, "e")
TestKit.check(kit, "second push over cap: dropped is 2", RewindHistory.dropped(h) == 2)
TestKit.check(kit, "second push over cap: toArray is oldest-first", RewindHistory.toArray(h) == ["c", "d", "e"])
TestKit.check(kit, "cap stays constant across pushes", RewindHistory.cap(h) == 3)

// get is out of range below 0 and at/above length.
TestKit.check(kit, "get: negative index is None", RewindHistory.get(h, -1) == None)
TestKit.check(kit, "get: index == length is None", RewindHistory.get(h, RewindHistory.length(h)) == None)
TestKit.check(kit, "get: last valid index is the newest", RewindHistory.get(h, RewindHistory.length(h) - 1) == Some("e"))

// a returned t is never mutated by a later push (persistence / no shared mutation).
let base = RewindHistory.make(~cap=5, 1)
let afterA = RewindHistory.push(base, 2)
let _afterB = RewindHistory.push(afterA, 3)
TestKit.check(kit, "persistence: base is untouched by later pushes", RewindHistory.toArray(base) == [1])
TestKit.check(kit, "persistence: afterA is untouched by a later push", RewindHistory.toArray(afterA) == [1, 2])

// cap is clamped to at least 1, so make/push never produce an empty history.
let tiny = RewindHistory.make(~cap=0, "only")
TestKit.check(kit, "cap clamps to 1: length is 1", RewindHistory.length(tiny) == 1)
let tiny = RewindHistory.push(tiny, "next")
TestKit.check(kit, "cap clamps to 1: push still keeps 1 entry", RewindHistory.length(tiny) == 1)
TestKit.check(kit, "cap clamps to 1: the new value replaces the old", RewindHistory.toArray(tiny) == ["next"])

TestKit.finish(kit, "RewindHistoryTest")
