// Exercises RewindValue against real ReScript 12 runtime shapes: a variant
// with all three constructor kinds, a record touching every ambiguous
// field type (option/list/array/tuple/dict/poly-variant), nested options,
// a cycle built with a mutable field (not raw JS), an exception, and the
// four JS-native shapes (Map/Set/Date/Blob) plus a function. Truncation
// and diff get their own sections at the end.

let kit = TestKit.make()

// --- sample types --------------------------------------------------------

type msg = Increment | Add(int, int) | SetPoint({x: int, y: int})

type status = [#active | #inactive(string)]

type record = {
  label: string,
  qty: option<int>,
  tags: list<string>,
  scores: array<int>,
  point: (int, int),
  meta: Dict.t<string>,
  status: status,
}

type rec node = {mutable value: int, mutable next: option<node>}

type wrapT = {tag: string, items: list<int>}

exception MyError(string)

// A minimal constructor for a real Web Blob -- Node 22 has the global.
// Only used to build test data; RewindJs.res still holds the only bindings
// RewindValue itself uses to *read* one.
type blobHandle
@new external makeBlob: (array<string>, {"type": string}) => blobHandle = "Blob"

// --- variant: nullary / positional / inline-record ------------------------

TestKit.check(kit, "nullary ctor summary is quoted", RewindValue.summary(RewindValue.make(Increment)) == "\"Increment\"")
TestKit.check(kit, "nullary ctor msgSummary is bare", RewindValue.msgSummary(RewindValue.make(Increment)) == "Increment")
TestKit.check(kit, "positional ctor summary", RewindValue.summary(RewindValue.make(Add(1, 2))) == "Add(1, 2)")
TestKit.check(
  kit,
  "inline-record ctor summary",
  RewindValue.summary(RewindValue.make(SetPoint({x: 3, y: 4}))) == "SetPoint({x: 3, y: 4})",
)

let addChildren = RewindValue.children(RewindValue.make(Add(1, 2)))
TestKit.check(
  kit,
  "positional ctor children labels+values",
  switch addChildren {
  | [(l0, v0), (l1, v1)] =>
    l0 == "0" && l1 == "1" && RewindValue.summary(v0) == "1" && RewindValue.summary(v1) == "2"
  | _ => false
  },
)

let setPointChildren = RewindValue.children(RewindValue.make(SetPoint({x: 3, y: 4})))
TestKit.check(
  kit,
  "inline-record ctor children labels are field names",
  switch setPointChildren {
  | [(l0, v0), (l1, v1)] =>
    l0 == "x" && l1 == "y" && RewindValue.summary(v0) == "3" && RewindValue.summary(v1) == "4"
  | _ => false
  },
)

TestKit.check(kit, "bare poly variant summary is quoted (indistinguishable from a string)", RewindValue.summary(RewindValue.make(#active)) == "\"active\"")

// --- record: option / list / array / tuple / dict / poly-variant fields --

let sampleRecord = {
  label: "widget",
  qty: Some(5),
  tags: list{"a", "b"},
  scores: [10, 20, 30],
  point: (7, 8),
  meta: Dict.fromArray([("k", "v")]),
  status: #inactive("paused"),
}

let recordChildren = RewindValue.children(RewindValue.make(sampleRecord))
let recordLabels = Array.map(recordChildren, ((l, _)) => l)
TestKit.check(
  kit,
  "record children are the field names in declaration order",
  recordLabels == ["label", "qty", "tags", "scores", "point", "meta", "status"],
)

let fieldSummary = (label: string): string =>
  switch Array.find(recordChildren, ((l, _)) => l == label) {
  | Some((_, v)) => RewindValue.summary(v)
  | None => "<missing>"
  }

TestKit.check(kit, "record.label (string field)", fieldSummary("label") == "\"widget\"")
TestKit.check(
  kit,
  "record.qty (Some(5) fully unwraps to the bare number -- not \"Some(5)\")",
  fieldSummary("qty") == "5",
)
TestKit.check(kit, "record.tags (list)", fieldSummary("tags") == "list{\"a\", \"b\"}")
TestKit.check(kit, "record.scores (array)", fieldSummary("scores") == "[10, 20, 30]")
TestKit.check(
  kit,
  "record.point (tuple compiles to a plain array -- indistinguishable from one)",
  fieldSummary("point") == "[7, 8]",
)
TestKit.check(
  kit,
  "record.meta (Dict.t compiles to a plain object -- indistinguishable from a record)",
  fieldSummary("meta") == "{k: \"v\"}",
)
TestKit.check(kit, "record.status (poly variant with payload)", fieldSummary("status") == "#inactive(\"paused\")")

// --- nested options --------------------------------------------------------

let someNone: option<option<int>> = Some(None)
let someSomeNone: option<option<option<int>>> = Some(Some(None))
let doubleWrapped: option<option<int>> = Some(Some(5))

TestKit.check(kit, "Some(None)", RewindValue.summary(RewindValue.make(someNone)) == "Some(None)")
TestKit.check(kit, "Some(Some(None))", RewindValue.summary(RewindValue.make(someSomeNone)) == "Some(Some(None))")
TestKit.check(
  kit,
  "Some(Some(5)) fully unwraps to the bare number",
  RewindValue.summary(RewindValue.make(doubleWrapped)) == "5",
)
TestKit.check(kit, "None at top level", RewindValue.summary(RewindValue.make(None)) == "None")

// --- cycle via a mutable field (not raw JS) --------------------------------

let cyclic: node = {value: 1, next: None}
cyclic.next = Some(cyclic)

TestKit.check(
  kit,
  "self-referencing record shows <cycle> instead of looping",
  RewindValue.summary(RewindValue.make(cyclic)) == "{value: 1, next: <cycle>}",
)
TestKit.check(kit, "cyclic node is not a leaf", !RewindValue.isLeaf(RewindValue.make(cyclic)))
TestKit.check(kit, "cyclic node has 2 children", Array.length(RewindValue.children(RewindValue.make(cyclic))) == 2)

// --- JS Map / Set / Date / Blob / function ---------------------------------

let m = Map.make()
m->Map.set("x", 1)
m->Map.set("y", 2)
TestKit.check(kit, "Map summary", RewindValue.summary(RewindValue.make(m)) == "Map{\"x\" => 1, \"y\" => 2}")

let s = Set.make()
s->Set.add(1)
s->Set.add(2)
TestKit.check(kit, "Set summary", RewindValue.summary(RewindValue.make(s)) == "Set{1, 2}")

let validDate = Date.fromString("2024-01-15T00:00:00.000Z")
TestKit.check(
  kit,
  "valid Date summary shows the ISO string",
  RewindValue.summary(RewindValue.make(validDate)) == "Date(2024-01-15T00:00:00.000Z)",
)

let invalidDate = Date.fromString("not-a-date")
TestKit.check(
  kit,
  "invalid Date summary, no throw",
  RewindValue.summary(RewindValue.make(invalidDate)) == "Date(Invalid)",
)

let blob = makeBlob([String.repeat("a", 2048)], {"type": "text/plain"})
TestKit.check(kit, "Blob summary (size in KB + mime)", RewindValue.summary(RewindValue.make(blob)) == "<Blob 2.0 KB text/plain>")

let fn = (x: int) => x + 1
TestKit.check(kit, "function summary", RewindValue.summary(RewindValue.make(fn)) == "<function>")

// --- exception ---------------------------------------------------------

let myErr: exn = MyError("boom")
TestKit.check(
  kit,
  "exception summary (module-qualified tag, Error key skipped)",
  RewindValue.summary(RewindValue.make(myErr)) == "RewindValueTest.MyError(\"boom\")",
)

// --- same: physical equality, not structural -------------------------------

TestKit.check(kit, "same: equal primitives are same (value semantics)", RewindValue.same(RewindValue.make(5), RewindValue.make(5)))
TestKit.check(
  kit,
  "same: two separately-built equal-looking objects are NOT same",
  !RewindValue.same(RewindValue.make({"x": 1}), RewindValue.make({"x": 1})),
)
TestKit.check(kit, "same: the same reference is same", RewindValue.same(RewindValue.make(cyclic), RewindValue.make(cyclic)))

// --- truncation ----------------------------------------------------------

let longStr = String.repeat("x", 200)
let longSummary = RewindValue.summary(RewindValue.make(longStr))
TestKit.check(kit, "long string truncated to max+ellipsis (120 kept + 1)", String.length(longSummary) == 121)
TestKit.check(kit, "long string summary ends with an ellipsis", String.charAt(longSummary, 120) == "…")

let customMax = RewindValue.summary(~max=10, RewindValue.make(longStr))
TestKit.check(kit, "custom ~max is honored", String.length(customMax) == 11)

let wideArr = Array.fromInitializer(~length=15, i => i)
TestKit.check(
  kit,
  "wide array summary caps at 10 entries with a '... N more' tail",
  RewindValue.summary(RewindValue.make(wideArr)) == "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, … 5 more]",
)
TestKit.check(
  kit,
  "children() is NOT capped at 10 -- full list for a tree view",
  Array.length(RewindValue.children(RewindValue.make(wideArr))) == 15,
)

let shallow: array<array<int>> = [[1]]
TestKit.check(kit, "depth 2 does not truncate", RewindValue.summary(RewindValue.make(shallow)) == "[[1]]")

let deep: array<array<array<array<int>>>> = [[[[1]]]]
TestKit.check(
  kit,
  "depth 3+ collapses the nested container to an ellipsis",
  RewindValue.summary(RewindValue.make(deep)) == "[[[…]]]",
)

// --- diff ------------------------------------------------------------------

TestKit.check(
  kit,
  "diff of the same value is empty",
  Array.length(RewindValue.diff(RewindValue.make(sampleRecord), RewindValue.make(sampleRecord))) == 0,
)

type todo = {title: string, done: bool}
type todoState = {todos: array<todo>}

let stateA = {todos: [{title: "a", done: false}, {title: "b", done: false}]}
let stateB = {todos: [{title: "a", done: false}, {title: "b", done: true}]}
let todoChanges = RewindValue.diff(RewindValue.make(stateA), RewindValue.make(stateB))

TestKit.check(kit, "diff finds exactly the one real change", Array.length(todoChanges) == 1)
TestKit.check(
  kit,
  "diff path uses todos[1].done -- bracket for the index, dot for the field",
  switch todoChanges {
  | [c] => c.path == "todos[1].done" && c.before == Some("false") && c.after == Some("true")
  | _ => false
  },
)

let dictA = Dict.fromArray([("x", 1), ("y", 2)])
let dictB = Dict.fromArray([("x", 1), ("z", 3)])
let dictChanges = RewindValue.diff(RewindValue.make(dictA), RewindValue.make(dictB))
TestKit.check(kit, "diff of differing key sets finds 2 changes", Array.length(dictChanges) == 2)
TestKit.check(
  kit,
  "a key present only on the before side has after=None (not a None value)",
  Array.some(dictChanges, c => c.path == "y" && c.before == Some("2") && c.after == None),
)
TestKit.check(
  kit,
  "a key present only on the after side has before=None",
  Array.some(dictChanges, c => c.path == "z" && c.before == None && c.after == Some("3")),
)

let sharedList = list{1, 2, 3}
let wrapA = {tag: "A", items: sharedList}
let wrapB = {tag: "B", items: sharedList}
let wrapChanges = RewindValue.diff(RewindValue.make(wrapA), RewindValue.make(wrapB))
TestKit.check(
  kit,
  "diff skips a same-reference subtree instead of walking it",
  switch wrapChanges {
  | [c] => c.path == "tag" && c.before == Some("\"A\"") && c.after == Some("\"B\"")
  | _ => false
  },
)

let arrA = [1, 2, 3, 4, 5]
let arrB = [10, 20, 30, 40, 50]
let limited = RewindValue.diff(~limit=2, RewindValue.make(arrA), RewindValue.make(arrB))
TestKit.check(kit, "diff stops once it hits ~limit", Array.length(limited) == 2)

TestKit.finish(kit, "RewindValueTest")
