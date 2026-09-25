open RewindCore

// --- a small test msg type with a hand-written codec ----------------------
type testMsg = Increment | SetName(string)

let reduce = (model: int, m: testMsg): int =>
  switch m {
  | Increment => model + 1
  | SetName(_) => model
  }

let encode = (m: testMsg): JSON.t =>
  switch m {
  | Increment => JSON.Object(Dict.fromArray([("tag", JSON.Encode.string("Increment"))]))
  | SetName(name) =>
    JSON.Object(
      Dict.fromArray([
        ("tag", JSON.Encode.string("SetName")),
        ("name", JSON.Encode.string(name)),
      ]),
    )
  }

let decode = (json: JSON.t): result<testMsg, string> =>
  switch json {
  | JSON.Object(dict) =>
    switch Dict.get(dict, "tag") {
    | Some(JSON.String("Increment")) => Ok(Increment)
    | Some(JSON.String("SetName")) =>
      switch Dict.get(dict, "name") {
      | Some(JSON.String(name)) => Ok(SetName(name))
      | _ => Error("SetName: missing or non-string \"name\"")
      }
    | Some(JSON.String(other)) => Error(`unknown tag "${other}"`)
    | _ => Error("missing or non-string \"tag\"")
    }
  | _ => Error("expected a JSON object")
  }

let codec: RewindCodec.codec<testMsg> = {encode, decode}

let kit = TestKit.make()

// --- fileName --------------------------------------------------------------
TestKit.check(
  kit,
  "fileName: rewind-<name>-<count>.json",
  RewindCodec.fileName(~name="abc", ~count=5) == "rewind-abc-5.json",
)

// --- exportJson: shape ------------------------------------------------------
let t0 = init(~cap=10, ~recording=true, 0, 0.0)
let t1 = update(~reduce, t0, App(Increment, 1.0))
let t2 = update(~reduce, t1, App(SetName("a"), 2.0))
let t3 = update(~reduce, t2, App(Increment, 3.0))

switch RewindCodec.exportJson(~name="mysession", ~codec, t3) {
| Error(_) => TestKit.check(kit, "exportJson succeeds when nothing has been dropped", false)
| Ok(str) =>
  switch JSON.parseOrThrow(str) {
  | JSON.Object(dict) =>
    TestKit.check(kit, "exportJson: \"rewind\" is 1", Dict.get(dict, "rewind") == Some(JSON.Number(1.0)))
    TestKit.check(
      kit,
      "exportJson: \"name\" matches",
      Dict.get(dict, "name") == Some(JSON.String("mysession")),
    )
    TestKit.check(kit, "exportJson: \"count\" is the message count", Dict.get(dict, "count") == Some(JSON.Number(3.0)))
    switch Dict.get(dict, "messages") {
    | Some(JSON.Array(items)) =>
      TestKit.check(kit, "exportJson: \"messages\" has one entry per App, no init entry", Array.length(items) == 3)
    | _ => TestKit.check(kit, "exportJson: \"messages\" is an array", false)
    }
  | _ => TestKit.check(kit, "exportJson: output parses back to a JSON object", false)
  }
}

// --- exportJson: errors once the history has dropped entries --------------
let dropBase = init(~cap=2, ~recording=true, 0, 0.0)
let dropT1 = update(~reduce, dropBase, App(Increment, 1.0))
let dropT2 = update(~reduce, dropT1, App(Increment, 2.0))
TestKit.check(kit, "cap=2 setup actually dropped an entry", RewindHistory.dropped(dropT2.history) > 0)
switch RewindCodec.exportJson(~name="x", ~codec, dropT2) {
| Error(_) => TestKit.check(kit, "exportJson errors once the history has dropped entries", true)
| Ok(_) => TestKit.check(kit, "exportJson errors once the history has dropped entries", false)
}

// --- round trip: exportJson then importJson gives back the same messages --
switch RewindCodec.exportJson(~name="rt", ~codec, t3) {
| Error(_) => TestKit.check(kit, "round trip: exportJson succeeds", false)
| Ok(str) =>
  switch RewindCodec.importJson(~codec, str) {
  | Error(_) => TestKit.check(kit, "round trip: importJson succeeds", false)
  | Ok(msgs) =>
    TestKit.check(
      kit,
      "round trip: messages match what was recorded, in order",
      msgs == [Increment, SetName("a"), Increment],
    )
  }
}

// --- importJson: not JSON ---------------------------------------------------
switch RewindCodec.importJson(~codec, "not json {{{") {
| Error(_) => TestKit.check(kit, "importJson: not-JSON input errors", true)
| Ok(_) => TestKit.check(kit, "importJson: not-JSON input errors", false)
}

// --- importJson: missing "rewind" -------------------------------------------
switch RewindCodec.importJson(~codec, "{}") {
| Error(_) => TestKit.check(kit, "importJson: missing \"rewind\" field errors", true)
| Ok(_) => TestKit.check(kit, "importJson: missing \"rewind\" field errors", false)
}

// --- importJson: wrong "rewind" version --------------------------------------
switch RewindCodec.importJson(~codec, `{"rewind":2,"name":"x","count":0,"messages":[]}`) {
| Error(_) => TestKit.check(kit, "importJson: unsupported \"rewind\" version errors", true)
| Ok(_) => TestKit.check(kit, "importJson: unsupported \"rewind\" version errors", false)
}

// --- importJson: "messages" is not an array ---------------------------------
switch RewindCodec.importJson(~codec, `{"rewind":1,"name":"x","count":0,"messages":"nope"}`) {
| Error(_) => TestKit.check(kit, "importJson: non-array \"messages\" errors", true)
| Ok(_) => TestKit.check(kit, "importJson: non-array \"messages\" errors", false)
}

// --- importJson: message k fails, error names k and the decoder's text -----
switch RewindCodec.importJson(
  ~codec,
  `{"rewind":1,"name":"x","count":2,"messages":[{"tag":"Increment"},{"tag":"Bogus"}]}`,
) {
| Error(msg) =>
  TestKit.check(kit, "importJson: a bad message names its index", msg->String.includes("message 1"))
  TestKit.check(kit, "importJson: a bad message includes the decoder's text", msg->String.includes("unknown tag"))
| Ok(_) => TestKit.check(kit, "importJson: a message that fails to decode errors", false)
}

// --- importJson: an empty messages array is fine (0 messages) ---------------
switch RewindCodec.importJson(~codec, `{"rewind":1,"name":"x","count":0,"messages":[]}`) {
| Ok(msgs) => TestKit.check(kit, "importJson: an empty messages array decodes to []", msgs == [])
| Error(_) => TestKit.check(kit, "importJson: an empty messages array is not an error", false)
}

TestKit.finish(kit, "RewindCodecTest")
