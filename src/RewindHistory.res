// A persistent history with a cap. `push` never mutates a `t` that was
// already returned: it always builds a fresh `items` array (via `concat` /
// `sliceToEnd`, never the in-place `Array.push`), so an old `t` a caller is
// still holding stays exactly as it was. That matters because React can
// call a reducer twice (Strict Mode) and both calls must be safe to keep.
//
// O(length) per push is fine (per spec) — `items` is a plain array, oldest
// entry first, capped at `cap`.
type t<'a> = {
  cap: int,
  items: array<'a>,
  dropped: int,
}

let make = (~cap: int, initial: 'a): t<'a> => {
  cap: Int.clamp(~min=1, cap),
  items: [initial],
  dropped: 0,
}

let push = (t: t<'a>, value: 'a): t<'a> => {
  let appended = Array.concat(t.items, [value])
  let overflow = Array.length(appended) - t.cap
  if overflow > 0 {
    {
      cap: t.cap,
      items: Array.slice(appended, ~start=overflow),
      dropped: t.dropped + overflow,
    }
  } else {
    {cap: t.cap, items: appended, dropped: t.dropped}
  }
}

let length = (t: t<'a>): int => Array.length(t.items)

let get = (t: t<'a>, index: int): option<'a> => Array.get(t.items, index)

let last = (t: t<'a>): 'a =>
  Array.get(t.items, Array.length(t.items) - 1)->Option.getOrThrow(
    ~message="RewindHistory.last: items is unexpectedly empty",
  )

let toArray = (t: t<'a>): array<'a> => Array.copy(t.items)

let dropped = (t: t<'a>): int => t.dropped
