// The value printer: turns an arbitrary runtime value into an inspectable,
// ReScript-syntax text representation, a labeled child list for a tree
// view, and a structural diff against another inspected value. See
// RewindValue.res for the printing rules pinned against the real ReScript
// 12 compiler output.

// One inspected runtime value. Immutable and cheap to hold onto -- `make`
// does not walk the value, so building a `t` is safe on a hot path.
type t

// `make(value)` captures `value` for inspection. Shallow, O(1): it is
// exactly `Type.Classify.classify`, so it does no work beyond reading
// `value`'s own runtime tag. Nothing is walked until `summary`, `children`
// or `diff` asks for it.
let make: 'a => t

// `summary(~max=120, t)` is one line of ReScript-syntax text for `t`,
// truncated at `max` characters (cut with a trailing "…"). A string value
// is always shown quoted, since a bare string and a nullary variant
// constructor are the same runtime value and can't be told apart -- see
// `msgSummary` for the one place that distinction is made.
let summary: (~max: int=?, t) => string

// `msgSummary(~max=120, t)` is `summary`, except that when `t` is itself a
// bare top-level string it is printed without quotes. rewind uses this for
// `msg` values: a nullary TEA message constructor (`Increment`) compiles to
// the bare JS string "Increment", indistinguishable at this level from a
// real string -- `summary` would quote it ("Increment"), `msgSummary`
// prints it the way the constructor reads in source (Increment). Only the
// top-level value gets this treatment; a string nested inside a container
// is still quoted, for the same reason `summary` always quotes strings.
let msgSummary: (~max: int=?, t) => string

// `children(t)` is `t`'s immediate labeled children, for a tree view: `[]`
// for a leaf. Labels follow the rules in RewindValue.res (record/dict
// keys, "0".."n" for constructor payloads/list/array items, a Map entry's
// key rendered with `summary`, a Set item's index). Unlike `summary`,
// `children` is not capped at 10 entries -- it always returns the full
// list, since a tree view can page or scroll a wide node itself.
let children: t => array<(string, t)>

// `isLeaf(t)` is `children(t) == []`, without building the array just to
// measure it.
let isLeaf: t => bool

// `same(a, b)` is physical equality of the underlying values `a` and `b`
// were made from (JS `===`; for an object, Map, Set, array etc. this means
// the same reference). Two equal-looking but separately-built values are
// not `same`. `diff` uses this to skip an unchanged subtree without
// walking it.
let same: (t, t) => bool

// One difference between two inspected values. `path` is the location,
// ReScript-ish: fields joined with ".", indexes in brackets, e.g.
// "todos[1].done"; the root path is "". `before`/`after` hold that
// location's printed form (via `summary`) on each side, or `None` when the
// key is absent on that side (not merely holding an absent/None value --
// see RewindValue.res for why that distinction needs an explicit presence
// check).
type change = {path: string, before: option<string>, after: option<string>}

// `diff(~limit=100, a, b)` walks `a` and `b` together and reports where
// they differ, stopping once it has collected `limit` changes. A subtree
// where `same(a, b)` holds is skipped without being walked. Two values are
// walked field-by-field/index-by-index only when they have the same
// recursable shape (both plain objects, by the union of their keys; both
// arrays or both lists, by index; the same variant TAG, by payload) --
// anything else, including two values that are both a Map, both a Set, or
// simply different shapes, is reported as one change at the current path
// instead of being walked further.
let diff: (~limit: int=?, t, t) => array<change>
