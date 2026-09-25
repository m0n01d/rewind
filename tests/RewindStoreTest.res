// Tests for RewindStore + RewindRegistry, through their public functions
// (neither module has a .resi, so every top-level binding here already IS
// the public surface). Same flat TestKit.check style as the other test
// files.
//
// RewindRegistry is process-wide, mutable, module-level state (see its own
// header comment) -- not something a test can get a fresh instance of. That
// is safe here only because `npm test` runs each `tests/*Test.res.mjs` file
// in its own `node` process (see package.json's `test` script), so this
// file's Registry block starts from an empty registry, and nothing earlier
// in this file touches RewindRegistry.

type testMsg = Add(int) | Reset

let reduce = (model: int, m: testMsg): int =>
  switch m {
  | Add(n) => model + n
  | Reset => 0
  }

let kit = TestKit.make()

// --- dispatch while paused ------------------------------------------------
let storePaused = RewindStore.make(~cap=10, ~recording=true, ~reduce, 0, 0.0)
let sessionPaused = RewindStore.makeSession(~name="dispatch-while-paused", ~store=storePaused, ())

storePaused.dispatch(Add(1))
storePaused.dispatch(Add(2))
storePaused.dispatch(Add(3)) // live: 0 -> 1 -> 3 -> 6; history indices 0..3, newest is 3

sessionPaused.jump(1) // a middle index, not the newest
TestKit.check(
  kit,
  "dispatch while paused: jump(1) pauses the cursor at 1",
  sessionPaused.getSnapshot().cursor == Some(1),
)

storePaused.dispatch(Add(4)) // one more App msg while still paused
TestKit.check(
  kit,
  "dispatch while paused: live still advances to reflect the new msg",
  RewindStore.getSnapshot(storePaused).live == 10,
)
TestKit.check(
  kit,
  "dispatch while paused: cursor stays on the paused entry, dispatch never auto-resumes",
  sessionPaused.getSnapshot().cursor == Some(1),
)

// --- jump ------------------------------------------------------------------
let storeJump = RewindStore.make(~cap=10, ~recording=true, ~reduce, 0, 0.0)
let sessionJump = RewindStore.makeSession(~name="jump", ~store=storeJump, ())

storeJump.dispatch(Add(1))
storeJump.dispatch(Add(2))
storeJump.dispatch(Add(3))
storeJump.dispatch(Add(4)) // history indices 0..4, newest is 4

sessionJump.jump(0)
TestKit.check(kit, "jump: cursor tracks index 0", sessionJump.getSnapshot().cursor == Some(0))
sessionJump.jump(2)
TestKit.check(kit, "jump: cursor tracks index 2", sessionJump.getSnapshot().cursor == Some(2))
sessionJump.jump(4) // the newest index
TestKit.check(
  kit,
  "jump: jumping to the newest index resumes to Live (cursor is None)",
  sessionJump.getSnapshot().cursor == None,
)

// --- resume ------------------------------------------------------------------
let storeResume = RewindStore.make(~cap=10, ~recording=true, ~reduce, 0, 0.0)
let sessionResume = RewindStore.makeSession(~name="resume", ~store=storeResume, ())

storeResume.dispatch(Add(1))
storeResume.dispatch(Add(2)) // history indices 0..2, newest is 2, live is 3

sessionResume.jump(0)
TestKit.check(kit, "resume: jump(0) pauses the cursor", sessionResume.getSnapshot().cursor == Some(0))

sessionResume.resume()
TestKit.check(kit, "resume: cursor is None (Live) after resume", sessionResume.getSnapshot().cursor == None)

let resumeSnap = sessionResume.getSnapshot()
switch resumeSnap.entry(resumeSnap.count) {
| None => TestKit.check(kit, "resume: entry(count) (the latest entry) exists", false)
| Some(e) =>
  // `RewindValue.same` is physical (JS ===) equality of the underlying
  // value -- fine here only because the test model is a primitive int.
  TestKit.check(
    kit,
    "resume: entry(count)'s model matches live",
    RewindValue.same(e.model, RewindValue.make(RewindStore.getSnapshot(storeResume).live)),
  )
  // Two separately-built values of the same variant shape are not `same`
  // (see RewindValue.resi), so messages are compared as text instead.
  TestKit.check(
    kit,
    "resume: entry(count)'s msg is the last dispatched message",
    switch e.msg {
    | None => false
    | Some(m) => RewindValue.msgSummary(m) == RewindValue.msgSummary(RewindValue.make(Add(2)))
    },
  )
}

// --- cap drop ----------------------------------------------------------
let storeCapDrop = RewindStore.make(~cap=3, ~recording=true, ~reduce, 0, 0.0)
let sessionCapDrop = RewindStore.makeSession(~name="cap-drop", ~store=storeCapDrop, ())

storeCapDrop.dispatch(Add(1))
storeCapDrop.dispatch(Add(2)) // history is [0, 1, 3], length 3 == cap, no drop yet

sessionCapDrop.jump(1) // pause on the entry holding model 1, not the oldest (0)
TestKit.check(kit, "cap drop: jump(1) pauses the cursor", sessionCapDrop.getSnapshot().cursor == Some(1))

switch sessionCapDrop.getSnapshot().entry(0) {
| None => TestKit.check(kit, "cap drop: entry(0) exists before the drop", false)
| Some(e) =>
  TestKit.check(
    kit,
    "cap drop: before the drop, entry(0) is the init entry (model 0)",
    RewindValue.same(e.model, RewindValue.make(0)),
  )
}

storeCapDrop.dispatch(Add(3)) // pushes past cap 3 -> evicts the init entry (model 0)

TestKit.check(kit, "cap drop: dropped is now greater than 0", sessionCapDrop.getSnapshot().dropped > 0)
TestKit.check(
  kit,
  "cap drop: the paused cursor survives the drop, reindexed from 1 to 0",
  sessionCapDrop.getSnapshot().cursor == Some(0),
)
switch sessionCapDrop.getSnapshot().entry(0) {
| None => TestKit.check(kit, "cap drop: entry(0) exists after the drop", false)
| Some(e) =>
  TestKit.check(
    kit,
    "cap drop: after the drop, entry(0) reads the surviving entry (model 1), not the evicted one",
    RewindValue.same(e.model, RewindValue.make(1)),
  )
}

// --- enabled=false keeps no history ---------------------------------------
let storeOff = RewindStore.make(~cap=10, ~recording=false, ~reduce, 0, 0.0)
let sessionOff = RewindStore.makeSession(~name="recording-false", ~store=storeOff, ())

storeOff.dispatch(Add(1))
storeOff.dispatch(Add(2))
storeOff.dispatch(Add(3))

TestKit.check(kit, "recording=false: count is 0, only the init entry exists", sessionOff.getSnapshot().count == 0)
TestKit.check(kit, "recording=false: nothing was ever dropped", sessionOff.getSnapshot().dropped == 0)
TestKit.check(
  kit,
  "recording=false: live still advances even though nothing is recorded",
  RewindStore.getSnapshot(storeOff).live == 6,
)

// --- RewindRegistry ----------------------------------------------------
let mkPair = (name: string) => {
  let store = RewindStore.make(~cap=10, ~recording=true, ~reduce, 0, 0.0)
  (store, RewindStore.makeSession(~name, ~store, ()))
}

TestKit.check(kit, "registry: empty before anything is added", RewindRegistry.getSnapshot()->Array.length == 0)
TestKit.check(kit, "registry: anyPaused is false initially", !RewindRegistry.anyPaused())

let notifyCount = ref(0)
let unsubscribe = RewindRegistry.subscribe(() => notifyCount := notifyCount.contents + 1)

let (storeA, sessionA) = mkPair("app")
RewindRegistry.add(sessionA)
TestKit.check(kit, "registry: add: the subscribe callback fires", notifyCount.contents == 1)
TestKit.check(
  kit,
  "registry: add: getSnapshot lists the one session",
  RewindRegistry.getSnapshot()->Array.length == 1,
)
TestKit.check(kit, "registry: add: an uncontested name is unchanged", sessionA.name == "app")

let (_, sessionB) = mkPair("app") // colliding name
RewindRegistry.add(sessionB)
TestKit.check(kit, "registry: add: the subscribe callback fires again", notifyCount.contents == 2)
TestKit.check(
  kit,
  "registry: add: getSnapshot lists both sessions",
  RewindRegistry.getSnapshot()->Array.length == 2,
)
TestKit.check(kit, "registry: uniqueName: a colliding name is disambiguated", sessionB.name == "app #2")

let notifyBeforeInternalChanges = notifyCount.contents
storeA.dispatch(Add(1))
storeA.dispatch(Add(2)) // history indices 0..2, newest is 2
sessionA.jump(1) // a session's own state change -- not a registry add/remove
TestKit.check(
  kit,
  "registry: subscribe: a session's own internal state change does not notify the registry",
  notifyCount.contents == notifyBeforeInternalChanges,
)

TestKit.check(
  kit,
  "registry: anyPaused: true once a session is paused at a non-newest index",
  RewindRegistry.anyPaused(),
)

sessionA.resume()
TestKit.check(kit, "registry: anyPaused: false again once that session resumes", !RewindRegistry.anyPaused())

let notifyBeforeRemove = notifyCount.contents
RewindRegistry.remove(sessionA)
TestKit.check(kit, "registry: remove: the subscribe callback fires", notifyCount.contents == notifyBeforeRemove + 1)
TestKit.check(
  kit,
  "registry: remove: getSnapshot drops the removed session",
  RewindRegistry.getSnapshot()->Array.length == 1 &&
    !(RewindRegistry.getSnapshot()->Array.some(s => s.id == sessionA.id)),
)
TestKit.check(
  kit,
  "registry: remove: the other session is still listed",
  RewindRegistry.getSnapshot()->Array.some(s => s.id == sessionB.id),
)

RewindRegistry.remove(sessionB)
unsubscribe()
TestKit.check(kit, "registry: cleanup: getSnapshot is empty again", RewindRegistry.getSnapshot()->Array.length == 0)

TestKit.finish(kit, "RewindStoreTest")
