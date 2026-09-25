// The value printer: turns an arbitrary runtime value into an inspectable,
// ReScript-syntax text representation, a labeled child list for a tree
// view, and a structural diff against another inspected value.
//
// Pinned against the real ReScript 12 compiler output (compiled small
// samples and read the generated .mjs to confirm each of these):
//   - a nullary constructor (`Increment`, incl. a pure-enum variant like
//     `Red`) compiles to the bare JS string "Increment" -- runtime-identical
//     to a real string. msgSummary exists only because of this.
//   - a positional-payload constructor (`Add(1,2)`) compiles to
//     {TAG:"Add", _0:1, _1:2}, 0-indexed.
//   - an inline-record-payload constructor (`Set({x:1,y:2})`) compiles to
//     {TAG:"Set", x:1, y:2} -- the field keys sit next to TAG directly.
//   - a bare poly variant (`#a`) is the bare string "a"; a poly variant with
//     a payload (`#b(5)`) is {NAME:"b", VAL:5}.
//   - `None` is JS `undefined`. `Some(x)` for any x that isn't itself an
//     option is literally `x`, fully unwrapped -- `Some(Some(1))` is `1`.
//     `Some(None)` is {BS_PRIVATE_NESTED_SOME_NONE:0}; each further nested
//     `Some(...None)` increments that number by one.
//   - `list{}` is the JS number 0 (not distinguishable from numeric zero --
//     a real, documented limitation of shallow inspection).
//     `list{1,2,3}` is {hd:1, tl:{hd:2, tl:{hd:3, tl:0}}}.
//   - an exception constructor is 1-indexed (`_1`, `_2`, ...), unlike a
//     variant's 0-indexing: `MyError("boom")` is
//     {RE_EXN_ID:"Module.MyError", _1:"boom", Error: new Error()}. A
//     zero-argument exception keeps the object wrapper (no `_N` keys) --
//     {RE_EXN_ID:"Module.NoArg", Error: new Error()} -- unlike a
//     zero-argument variant, which is a bare string.
//   - a tuple and a record both compile to a plain JS value ([1,"y"] / a
//     plain object) -- runtime-indistinguishable from an array / a Dict.t.
//   - unit `()` is JS `undefined` -- indistinguishable from `None`.

// One inspected runtime value, together with the one place a JS read is
// allowed to fail: `Unreadable` marks a child whose read threw (a poisoned
// getter -- see readChild below), standing in for it instead of letting the
// exception escape this module. `make` never produces `Unreadable`; only
// the internal child-reading during `render`/`children`/`diff` can.
type t = Value(Type.Classify.t) | Unreadable

// The default `~max`/character budget for one line of `summary` text, and
// for a Map entry's key label (which has no caller-supplied max of its
// own -- see entriesFor's OMap case).
let defaultMax = 120

// Cuts `s` to at most `max` characters, replacing anything past that with a
// single trailing "…".
let truncate = (s: string, max: int): string =>
  if String.length(s) > max {
    String.slice(s, ~start=0, ~end=max) ++ "…"
  } else {
    s
  }

let hasKey = (ks: array<string>, k: string): bool => Array.some(ks, x => x == k)

let isDigit = (c: string): bool => c >= "0" && c <= "9"

let isAllDigits = (s: string): bool => {
  let len = String.length(s)
  let rec go = i => i >= len || (isDigit(String.charAt(s, i)) && go(i + 1))
  len > 0 && go(0)
}

// "_3" -> Some(3); anything else (including bare "_", or a non-digit tail)
// -> None. Used to tell a positional payload key ("_0", "_1", ...) apart
// from an inline record's own field that happens to start with "_".
let parseUnderscoreIndex = (key: string): option<int> =>
  if String.length(key) > 1 && String.charAt(key, 0) == "_" {
    let rest = String.slice(key, ~start=1)
    if isAllDigits(rest) {
      Int.fromString(rest)
    } else {
      None
    }
  } else {
    None
  }

// "[object Map]" -> "Map". Falls back to the untouched string if it isn't
// wrapped the usual way, which only happens if Symbol.toStringTag was
// monkey-patched to return something nonstandard.
let extractTag = (tagStr: string): string => {
  let prefix = "[object "
  let plen = String.length(prefix)
  let len = String.length(tagStr)
  if String.startsWith(tagStr, prefix) && len > plen && String.charAt(tagStr, len - 1) == "]" {
    String.slice(tagStr, ~start=plen, ~end=len - 1)
  } else {
    tagStr
  }
}

// Blob/File sizes are shown in kibibytes to one decimal place -- the
// brief's own example is "12.3 KB" and gives no other unit to scale to, so
// this doesn't invent a B/MB/GB ladder beyond that.
let formatBytes = (bytes: float): string => Float.toFixed(bytes /. 1024.0, ~digits=1) ++ " KB"

// Calls a JS read that isn't a plain compiler-generated data property (a
// tag getter, a Blob/File property) and substitutes `fallback` instead of
// letting a throw from it escape this module.
let tryOr = (f: unit => 'a, fallback: 'a): 'a =>
  switch f() {
  | v => v
  | exception JsExn(_) => fallback
  }

// Reads and classifies one field in a single step, catching a throwing
// getter (see RewindJs.getField's doc comment) instead of propagating it.
// This is the only place a child `t` is built from a field read, so it's
// the one place `Unreadable` is ever produced.
let readChild = (o: Type.Classify.object, k: string): t =>
  switch RewindJs.getField(o, k) {
  | u => Value(RewindJs.classifyUnknown(u))
  | exception JsExn(_) => Unreadable
  }

// TAG / RE_EXN_ID / NAME are always plain data properties on a real
// compiler-generated shape (never a user getter), so this can't throw in
// practice -- it still goes through readChild for a single safe code path,
// and falls back to "" if the field isn't the expected string.
let readTagField = (o: Type.Classify.object, k: string): string =>
  switch readChild(o, k) {
  | Value(String(s)) => s
  | _ => ""
  }

// Walks a {hd, tl} cons chain from `o` (already confirmed to have that
// shape) to the terminal `0`, collecting `hd` at each step. Stops instead
// of looping forever if the chain revisits an object already on the path.
let walkList = (o: Type.Classify.object): array<t> => {
  let items = []
  let rec go = (current: Type.Classify.object, seen: list<Type.Classify.object>) =>
    if List.some(seen, s => s === current) {
      ()
    } else {
      let ks = RewindJs.keys(current)
      if Array.length(ks) == 2 && hasKey(ks, "hd") && hasKey(ks, "tl") {
        Array.push(items, readChild(current, "hd"))
        switch readChild(current, "tl") {
        | Value(Object(next)) => go(next, list{current, ...seen})
        | _ => ()
        }
      }
    }
  go(o, list{})
  items
}

// Date(iso) / Date(Invalid), never throwing: String(x) on a Date can't
// throw and gives "Invalid Date" for an invalid one, so it's a safe
// pre-check; .toJSON() then gives the ISO text (JS null instead of
// throwing for an invalid date, per spec).
let readDateIso = (o: Type.Classify.object): option<string> =>
  switch tryOr(() => RewindJs.stringOf(o), "") {
  | "Invalid Date" => None
  | _ =>
    switch RewindJs.classifyUnknown(RewindJs.dateToJSON(o)) {
    | String(iso) => Some(iso)
    | _ => None
    | exception JsExn(_) => None
    }
  }

// The shape an Object(...) resolves to, with every child already read (and
// safety-wrapped) into a `t`. Priority order matches the compiler-output
// survey above: the option marker is checked first since it's otherwise a
// plain object with one numeric-looking field, then TAG, then NAME/VAL,
// then RE_EXN_ID, then the {hd,tl} list shape, then Array.isArray, and only
// then the toString-tag dispatch for Map/Set/Date/Blob/File/plain object.
type objShape =
  | ONestedNone(int)
  | OVariantPositional(string, array<t>)
  | OVariantRecord(string, array<(string, t)>)
  | OPolyVariant(string, t)
  | OException(string, array<t>)
  | OList(array<t>)
  | OArray(array<t>)
  | OMap(array<(t, t)>)
  | OSet(array<t>)
  | ODate(option<string>)
  | OBlob(float, string)
  | OFile(float, string)
  | OReactElement
  | OPlainObject(array<(string, t)>)
  | OOther(string)

let classifyObject = (o: Type.Classify.object): objShape => {
  let ks = RewindJs.keys(o)
  if hasKey(ks, "BS_PRIVATE_NESTED_SOME_NONE") {
    let n = switch readChild(o, "BS_PRIVATE_NESTED_SOME_NONE") {
    | Value(Number(n)) => Float.toInt(n)
    | _ => 0
    }
    ONestedNone(n)
  } else if hasKey(ks, "TAG") {
    let tag = readTagField(o, "TAG")
    let rest = Array.filter(ks, k => k != "TAG")
    let n = Array.length(rest)
    let allPositional = n == 0 || Array.every(rest, k => Option.isSome(parseUnderscoreIndex(k)))
    if allPositional {
      OVariantPositional(
        tag,
        Array.fromInitializer(~length=n, i => readChild(o, "_" ++ Int.toString(i))),
      )
    } else {
      OVariantRecord(tag, Array.map(rest, k => (k, readChild(o, k))))
    }
  } else if hasKey(ks, "NAME") && hasKey(ks, "VAL") {
    OPolyVariant(readTagField(o, "NAME"), readChild(o, "VAL"))
  } else if hasKey(ks, "RE_EXN_ID") {
    let tag = readTagField(o, "RE_EXN_ID")
    let rest = Array.filter(ks, k => k != "RE_EXN_ID" && k != "Error")
    let n = Array.length(rest)
    OException(
      tag,
      Array.fromInitializer(~length=n, i => readChild(o, "_" ++ Int.toString(i + 1))),
    )
  } else if Array.length(ks) == 2 && hasKey(ks, "hd") && hasKey(ks, "tl") {
    OList(walkList(o))
  } else if RewindJs.isArray(o) {
    OArray(Array.map(RewindJs.arrayFrom(o), u => Value(RewindJs.classifyUnknown(u))))
  } else {
    let tagStr = tryOr(() => RewindJs.toStringTag(o), "[object Object]")
    switch extractTag(tagStr) {
    | "Map" =>
      OMap(
        Array.map(RewindJs.arrayFrom(o), entryU =>
          switch RewindJs.classifyUnknown(entryU) {
          | Object(entryObj) => (readChild(entryObj, "0"), readChild(entryObj, "1"))
          | _ => (Unreadable, Unreadable)
          }
        ),
      )
    | "Set" => OSet(Array.map(RewindJs.arrayFrom(o), u => Value(RewindJs.classifyUnknown(u))))
    | "Date" => ODate(readDateIso(o))
    | "Blob" =>
      OBlob(tryOr(() => RewindJs.blobSize(o), 0.0), tryOr(() => RewindJs.blobType(o), ""))
    | "File" =>
      OFile(tryOr(() => RewindJs.blobSize(o), 0.0), tryOr(() => RewindJs.fileName(o), ""))
    | "Object" =>
      if hasKey(ks, "$$typeof") {
        OReactElement
      } else {
        OPlainObject(Array.map(ks, k => (k, readChild(o, k))))
      }
    | other => OOther(other)
    }
  }
}

// How a container's entries join: bare ("1", "2") for a positional
// payload/array/list/set, or "label: value"/"label => value" for a keyed
// one.
type entryStyle = EBare | ELabeled(string)

let rec render = (v: t, ~depth: int, ~ancestors: list<Type.Classify.object>): string =>
  switch v {
  | Unreadable => "<error>"
  | Value(Bool(b)) => b ? "true" : "false"
  | Value(Null) => "null"
  | Value(Undefined) => "None"
  | Value(String(s)) => JSON.stringify(JSON.String(s))
  | Value(Number(n)) => Float.toString(n)
  | Value(Function(_)) => "<function>"
  | Value(Symbol(s)) => Symbol.toString(s)
  | Value(BigInt(b)) => BigInt.toString(b) ++ "n"
  | Value(Object(o)) =>
    if List.some(ancestors, a => a === o) {
      "<cycle>"
    } else {
      renderShape(classifyObject(o), ~depth, ~ancestors=list{o, ...ancestors})
    }
  }
and renderShape = (shape: objShape, ~depth: int, ~ancestors: list<Type.Classify.object>): string =>
  switch shape {
  | ONestedNone(n) => String.repeat("Some(", n + 1) ++ "None" ++ String.repeat(")", n + 1)
  | ODate(Some(iso)) => "Date(" ++ iso ++ ")"
  | ODate(None) => "Date(Invalid)"
  | OBlob(size, mime) => "<Blob " ++ formatBytes(size) ++ " " ++ mime ++ ">"
  | OFile(size, name) => "<File " ++ name ++ " " ++ formatBytes(size) ++ ">"
  | OReactElement => "<React element>"
  | OOther(x) => "<" ++ x ++ ">"
  | OVariantPositional(tag, _) =>
    joinContainer(
      ~prefix=tag,
      ~opening="(",
      ~closing=")",
      ~style=EBare,
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OVariantRecord(tag, _) =>
    joinContainer(
      ~prefix=tag ++ "(",
      ~opening="{",
      ~closing="})",
      ~style=ELabeled(": "),
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OPolyVariant(tag, _) =>
    joinContainer(
      ~prefix="#" ++ tag,
      ~opening="(",
      ~closing=")",
      ~style=EBare,
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OException(tag, _) =>
    joinContainer(
      ~prefix=tag,
      ~opening="(",
      ~closing=")",
      ~style=EBare,
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OList(_) =>
    joinContainer(
      ~prefix="list",
      ~opening="{",
      ~closing="}",
      ~style=EBare,
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OArray(_) =>
    joinContainer(
      ~prefix="",
      ~opening="[",
      ~closing="]",
      ~style=EBare,
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OMap(_) =>
    joinContainer(
      ~prefix="Map",
      ~opening="{",
      ~closing="}",
      ~style=ELabeled(" => "),
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OSet(_) =>
    joinContainer(
      ~prefix="Set",
      ~opening="{",
      ~closing="}",
      ~style=EBare,
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  | OPlainObject(_) =>
    joinContainer(
      ~prefix="",
      ~opening="{",
      ~closing="}",
      ~style=ELabeled(": "),
      ~entries=entriesFor(shape),
      ~depth,
      ~ancestors,
    )
  }
and joinContainer = (
  ~prefix: string,
  ~opening: string,
  ~closing: string,
  ~style: entryStyle,
  ~entries: array<(string, t)>,
  ~depth: int,
  ~ancestors: list<Type.Classify.object>,
): string => {
  let n = Array.length(entries)
  if depth >= 3 && n > 0 {
    "…"
  } else {
    let shown = if n > 10 {
      Array.slice(entries, ~start=0, ~end=10)
    } else {
      entries
    }
    let parts = Array.map(shown, ((label, childT)) => {
      let childStr = render(childT, ~depth=depth + 1, ~ancestors)
      switch style {
      | EBare => childStr
      | ELabeled(sep) => label ++ sep ++ childStr
      }
    })
    let allParts = if n > 10 {
      Array.concat(parts, [`… ${Int.toString(n - 10)} more`])
    } else {
      parts
    }
    prefix ++ opening ++ Array.join(allParts, ", ") ++ closing
  }
}
and entriesFor = (shape: objShape): array<(string, t)> =>
  switch shape {
  | ONestedNone(_)
  | ODate(_)
  | OBlob(_, _)
  | OFile(_, _)
  | OReactElement
  | OOther(_) => []
  | OVariantPositional(_, args) => Array.mapWithIndex(args, (v, i) => (Int.toString(i), v))
  | OVariantRecord(_, fields) => fields
  | OPolyVariant(_, payload) => [("0", payload)]
  | OException(_, args) => Array.mapWithIndex(args, (v, i) => (Int.toString(i + 1), v))
  | OList(items) => Array.mapWithIndex(items, (v, i) => (Int.toString(i), v))
  | OArray(items) => Array.mapWithIndex(items, (v, i) => (Int.toString(i), v))
  | OMap(pairs) =>
    Array.map(pairs, ((k, v)) => (truncate(render(k, ~depth=0, ~ancestors=list{}), defaultMax), v))
  | OSet(items) => Array.mapWithIndex(items, (v, i) => (Int.toString(i), v))
  | OPlainObject(fields) => fields
  }

let make = (value: 'a): t => Value(Type.Classify.classify(value))

let summary = (~max=?, v: t): string =>
  truncate(render(v, ~depth=0, ~ancestors=list{}), Option.getOr(max, defaultMax))

let msgSummary = (~max=?, v: t): string =>
  switch v {
  | Value(String(s)) => truncate(s, Option.getOr(max, defaultMax))
  | _ => summary(~max?, v)
  }

let children = (v: t): array<(string, t)> =>
  switch v {
  | Value(Object(o)) => entriesFor(classifyObject(o))
  | _ => []
  }

let isLeaf = (v: t): bool => Array.length(children(v)) == 0

let same = (a: t, b: t): bool =>
  switch (a, b) {
  | (Value(x), Value(y)) =>
    switch (x, y) {
    | (Bool(p), Bool(q)) => p === q
    | (Null, Null) => true
    | (Undefined, Undefined) => true
    | (String(p), String(q)) => p === q
    | (Number(p), Number(q)) => p === q
    | (Object(p), Object(q)) => p === q
    | (Function(p), Function(q)) => p === q
    | (Symbol(p), Symbol(q)) => p === q
    | (BigInt(p), BigInt(q)) => p === q
    | _ => false
    }
  | _ => false
  }

type change = {path: string, before: option<string>, after: option<string>}

let fieldPath = (base: string, key: string): string => base == "" ? key : base ++ "." ++ key

// The union of two entry lists' labels, A's own order first, then any of
// B's labels A doesn't have, in B's order -- deterministic without needing
// a set/dict type.
let unionLabels = (entriesA: array<(string, t)>, entriesB: array<(string, t)>): array<string> => {
  let labelsA = Array.map(entriesA, ((k, _)) => k)
  let labelsB = Array.map(entriesB, ((k, _)) => k)
  let extra = Array.filter(labelsB, k => !Array.some(labelsA, k2 => k2 == k))
  Array.concat(labelsA, extra)
}

let lookupLabel = (entries: array<(string, t)>, label: string): option<t> =>
  switch Array.find(entries, ((k, _)) => k == label) {
  | Some((_, v)) => Some(v)
  | None => None
  }

// A fingerprint for "the same recursable shape": Some(_) only for the
// container kinds diff is willing to walk field-by-field/index-by-index
// (plain objects, arrays, lists, and same-TAG variants/exceptions/poly
// variants), None for everything diff treats as opaque (Map, Set, Date,
// Blob, File, a React element, the Some(None) marker, an unrecognized
// tag) -- those are always reported as one change instead of walked.
let diffTag = (shape: objShape): option<string> =>
  switch shape {
  | OPlainObject(_) => Some("object")
  | OArray(_) => Some("array")
  | OList(_) => Some("list")
  | OVariantPositional(tag, _) => Some("variant:" ++ tag)
  | OVariantRecord(tag, _) => Some("variant:" ++ tag)
  | OPolyVariant(tag, _) => Some("poly:" ++ tag)
  | OException(tag, _) => Some("exn:" ++ tag)
  | ONestedNone(_)
  | OMap(_)
  | OSet(_)
  | ODate(_)
  | OBlob(_, _)
  | OFile(_, _)
  | OReactElement
  | OOther(_) => None
  }

let diff = (~limit=100, a: t, b: t): array<change> => {
  let results: array<change> = []
  let rec go = (path: string, va: t, vb: t) =>
    if Array.length(results) >= limit {
      ()
    } else if same(va, vb) {
      ()
    } else {
      switch (va, vb) {
      | (Value(Object(oa)), Value(Object(ob))) =>
        let shapeA = classifyObject(oa)
        let shapeB = classifyObject(ob)
        switch (diffTag(shapeA), diffTag(shapeB)) {
        | (Some(ta), Some(tb)) if ta == tb =>
          let entriesA = entriesFor(shapeA)
          let entriesB = entriesFor(shapeB)
          Array.forEach(unionLabels(entriesA, entriesB), label =>
            if Array.length(results) < limit {
              let childPath = isAllDigits(label) ? path ++ "[" ++ label ++ "]" : fieldPath(path, label)
              switch (lookupLabel(entriesA, label), lookupLabel(entriesB, label)) {
              | (Some(ca), Some(cb)) => go(childPath, ca, cb)
              | (Some(ca), None) =>
                Array.push(results, {path: childPath, before: Some(summary(ca)), after: None})
              | (None, Some(cb)) =>
                Array.push(results, {path: childPath, before: None, after: Some(summary(cb))})
              | (None, None) => ()
              }
            }
          )
        | _ => Array.push(results, {path, before: Some(summary(va)), after: Some(summary(vb))})
        }
      | _ => Array.push(results, {path, before: Some(summary(va)), after: Some(summary(vb))})
      }
    }
  go("", a, b)
  results
}
