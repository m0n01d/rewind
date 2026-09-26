// Proof for review finding M3 (S/review-rewind.md): the old `rows`
// recursion in RewindPanel.res's SessionDetail.make cost one JS stack
// frame per history entry (non-tail `Array.concat([row], rows(i + 1))`),
// and blew the stack on a capped history well under the default cap of
// 10000 (measured by the review: RangeError at 6000-7000 in Node,
// depending on NODE_ENV).
//
// The fix, `RewindPanel.messageRows`, builds the same row array with
// `Array.fromInitializer`, which does not recurse. This test drives a
// real store and session to a 10000-entry history (the documented default
// cap) and calls the fixed helper directly -- no React render needed,
// since JSX for a host element like `<div>` just builds a plain element
// record, so this runs in plain Node like the other *Test.res files.

type testMsg = Tick

let reduce = (model: int, _: testMsg): int => model + 1

let kit = TestKit.make()

let entryCount = 10000

// Cap well above entryCount so nothing drops, and count == entryCount.
let store = RewindStore.make(~cap=20000, ~recording=true, ~reduce, 0, 0.0)
let session = RewindStore.makeSession(~name="rows-stress", ~store, ())

for _ in 1 to entryCount {
  store.dispatch(Tick)
}

let snapshot = session.getSnapshot()
TestKit.check(kit, "history grew to the full entry count, nothing dropped", snapshot.count == entryCount)

// Reaching this line at all -- the old recursive `rows` threw a
// RangeError well below this size -- plus the right length, is the proof.
let rows = RewindPanel.messageRows(~snapshot, ~selected=snapshot.count, ~onRowClick=_ => ())

TestKit.check(
  kit,
  "messageRows renders the full 10000-entry history (Init + one row per message), no stack overflow",
  Array.length(rows) == entryCount + 1,
)

TestKit.finish(kit, "RewindPanelRowsTest")
