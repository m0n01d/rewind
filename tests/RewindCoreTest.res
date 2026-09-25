open RewindCore

type testMsg = Add(int) | Reset

let reduce = (model: int, m: testMsg): int =>
  switch m {
  | Add(n) => model + n
  | Reset => 0
  }

let kit = TestKit.make()

// --- init --------------------------------------------------------------
let t0 = init(~cap=3, ~recording=true, 0, 0.0)
TestKit.check(kit, "init: initial is the given model", t0.initial == 0)
TestKit.check(kit, "init: live is the given model", t0.live == 0)
TestKit.check(kit, "init: cursor is Live", t0.cursor == Live)
TestKit.check(kit, "init: recording is what was passed", t0.recording == true)
TestKit.check(kit, "init: history length is 1", RewindHistory.length(t0.history) == 1)
let seed = RewindHistory.last(t0.history)
TestKit.check(kit, "init: the seed entry has msg None", seed.msg == None)
TestKit.check(kit, "init: the seed entry model is the given model", seed.model == 0)
TestKit.check(kit, "init: the seed entry time is the given time", seed.time == 0.0)

// --- rule 1: App while Live ---------------------------------------------
let t1 = update(~reduce, t0, App(Add(1), 1.0))
TestKit.check(kit, "App: live advances via reduce", t1.live == 1)
TestKit.check(kit, "App: cursor stays Live", t1.cursor == Live)
TestKit.check(kit, "App: history grows by one", RewindHistory.length(t1.history) == 2)
let newest = RewindHistory.last(t1.history)
TestKit.check(kit, "App: newest entry model is live", newest.model == 1)
TestKit.check(kit, "App: newest entry msg is Some(the message)", newest.msg == Some(Add(1)))
TestKit.check(kit, "App: newest entry time is the given time", newest.time == 1.0)

// fill to cap (cap=3) for the cap-shift test below.
let t2 = update(~reduce, t1, App(Add(1), 2.0))
TestKit.check(kit, "history reaches cap", RewindHistory.length(t2.history) == 3)

// --- rule 2: Jump --------------------------------------------------------
let t3 = update(~reduce, t2, Jump(1))
TestKit.check(kit, "Jump(1): cursor is Paused(1)", t3.cursor == Paused(1))
TestKit.check(kit, "Jump(1): view gives entry 1's model", view(t3) == 1)
TestKit.check(kit, "Jump(1): isPaused is true", isPaused(t3))
TestKit.check(kit, "Jump(1): live is unaffected", t3.live == 2)

// --- rule 1 continued: App while Paused, at cap -> the cap-shift case ---
let t4 = update(~reduce, t3, App(Add(1), 3.0))
TestKit.check(kit, "App while paused: live still advances", t4.live == 3)
TestKit.check(
  kit,
  "App while paused at cap: the push drops one, cursor shifts Paused(1) -> Paused(0)",
  t4.cursor == Paused(0),
)
TestKit.check(
  kit,
  "App while paused at cap: view still shows the SAME entry (model 1), not a different one",
  view(t4) == 1,
)
TestKit.check(kit, "App while paused at cap: history length stays at cap", RewindHistory.length(t4.history) == 3)
TestKit.check(
  kit,
  "App while paused at cap: the oldest entry (model 0) was dropped",
  RewindHistory.toArray(t4.history)->Array.map(e => e.model) == [1, 2, 3],
)

// Jump clamps to [0, length-1]; the newest index resumes Live (deviation from Elm).
let t5 = update(~reduce, t4, Jump(100))
TestKit.check(kit, "Jump beyond range clamps to the newest entry -> Live", t5.cursor == Live)

let t6 = update(~reduce, t4, Jump(-5))
TestKit.check(kit, "Jump below range clamps to 0 -> Paused(0)", t6.cursor == Paused(0))

let t7 = update(~reduce, t6, Jump(2))
TestKit.check(
  kit,
  "Jump to the newest index resumes to Live (deliberate deviation from Elm, which stays paused)",
  t7.cursor == Live,
)

// --- rule 3: Resume --------------------------------------------------------
let t8 = update(~reduce, t4, Jump(0))
let t9 = update(~reduce, t8, Resume)
TestKit.check(kit, "Resume: cursor is Live", t9.cursor == Live)
TestKit.check(kit, "Resume: view is live, not the previously-paused entry", view(t9) == t9.live)
TestKit.check(kit, "isPaused is false once resumed", !isPaused(t9))

// --- rule 4: Replace ---------------------------------------------------
let base = init(~cap=10, ~recording=true, 100, 0.0)
let afterA = update(~reduce, base, App(Add(5), 1.0)) // live=105
let paused = update(~reduce, afterA, Jump(0)) // Paused(0), live stays 105

let replaced = update(~reduce, paused, Replace([Add(1), Add(2), Add(3)], 9.0))
TestKit.check(
  kit,
  "Replace: live is a fresh replay from `initial`, not from the prior live (105)",
  replaced.live == 100 + 1 + 2 + 3,
)
TestKit.check(kit, "Replace: cursor is Live even though it was Paused before", replaced.cursor == Live)
TestKit.check(
  kit,
  "Replace: history length is the init entry plus one per msg",
  RewindHistory.length(replaced.history) == 4,
)
let replacedEntries = RewindHistory.toArray(replaced.history)
TestKit.check(
  kit,
  "Replace: every entry is timestamped with the given time",
  replacedEntries->Array.every(e => e.time == 9.0),
)
TestKit.check(
  kit,
  "Replace: the first entry is the init entry (msg None, model `initial`)",
  switch RewindHistory.get(replaced.history, 0) {
  | Some(e) => e.msg == None && e.model == 100
  | None => false
  },
)
TestKit.check(
  kit,
  "Replace: the model at each step matches replaying the messages in order",
  replacedEntries->Array.map(e => e.model) == [100, 101, 103, 106],
)

// Replace respects the existing cap (trims the replay, oldest first).
let smallCapBase = init(~cap=2, ~recording=true, 0, 0.0)
let trimmed = update(~reduce, smallCapBase, Replace([Add(1), Add(2), Add(3)], 5.0))
TestKit.check(kit, "Replace respects cap: history length stays at cap", RewindHistory.length(trimmed.history) == 2)
TestKit.check(kit, "Replace respects cap: live is still the full replay result", trimmed.live == 6)
TestKit.check(
  kit,
  "Replace respects cap: only the newest entries remain",
  RewindHistory.toArray(trimmed.history)->Array.map(e => e.model) == [3, 6],
)

// --- rule 5: recording=false ---------------------------------------------
let nr0 = init(~cap=3, ~recording=false, 0, 0.0)
let nr1 = update(~reduce, nr0, App(Add(7), 1.0))
TestKit.check(kit, "recording=false, App: live still advances", nr1.live == 7)
TestKit.check(kit, "recording=false, App: history is untouched", RewindHistory.length(nr1.history) == 1)
TestKit.check(kit, "recording=false, App: cursor stays Live", nr1.cursor == Live)

let nr2 = update(~reduce, nr1, Jump(0))
TestKit.check(kit, "recording=false, Jump: live is unchanged", nr2.live == nr1.live)
TestKit.check(
  kit,
  "recording=false, Jump: history is unchanged",
  RewindHistory.toArray(nr2.history) == RewindHistory.toArray(nr1.history),
)
TestKit.check(kit, "recording=false, Jump: cursor is unchanged", nr2.cursor == nr1.cursor)

let nr3 = update(~reduce, nr1, Resume)
TestKit.check(kit, "recording=false, Resume: live is unchanged", nr3.live == nr1.live)
TestKit.check(kit, "recording=false, Resume: cursor is unchanged", nr3.cursor == nr1.cursor)

let nr4 = update(~reduce, nr1, Replace([Add(99)], 2.0))
TestKit.check(kit, "recording=false, Replace: live is unchanged (not re-replayed)", nr4.live == nr1.live)
TestKit.check(
  kit,
  "recording=false, Replace: history is unchanged",
  RewindHistory.length(nr4.history) == RewindHistory.length(nr1.history),
)

// --- rule 6: view ----------------------------------------------------------
TestKit.check(kit, "view: Live gives live", view(t1) == t1.live)
TestKit.check(
  kit,
  "view: Paused(i) gives entry i's model, not live",
  view(t3) == 1 && t3.live != view(t3),
)

TestKit.finish(kit, "RewindCoreTest")
