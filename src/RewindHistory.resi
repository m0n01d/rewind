// A persistent history with a cap. See RewindHistory.res for the
// mutation-safety note (safe to hold across a doubled React reducer call).

type t<'a>

/** Creates a history that holds at most `cap` entries (clamped to at least
    1) and seeds it with one entry, `initial`. */
let make: (~cap: int, 'a) => t<'a>

/** Pushes a new value onto the end. Drops the oldest entry when the
    history is already at its cap. Returns a new history and never mutates
    the one passed in. */
let push: (t<'a>, 'a) => t<'a>

/** The number of entries currently retained (at most the cap given to
    `make`). */
let length: t<'a> => int

/** The entry at `index`, oldest first — `0` is the oldest retained entry.
    `None` when `index` is out of range. */
let get: (t<'a>, int) => option<'a>

/** The most recently pushed entry, or the `initial` entry if nothing has
    been pushed yet. */
let last: t<'a> => 'a

/** All retained entries, oldest first, as a fresh array. */
let toArray: t<'a> => array<'a>

/** How many entries `push` has dropped since `make`, because the history
    was at its cap. */
let dropped: t<'a> => int
