// JSON export/import for a codec-equipped app. Uses only the stdlib JSON
// module (node_modules/@rescript/runtime/lib/ocaml/Stdlib_JSON.resi), per
// the house rule on JSON decoding. The message shape itself belongs to the
// caller's codec; this module only owns the envelope.

type codec<'msg> = {
  encode: 'msg => JSON.t,
  decode: JSON.t => result<'msg, string>,
}

// The "rewind" field's expected value. Bumping this is a breaking change
// to the export format.
let formatVersion = 1

let fileName = (~name: string, ~count: int): string =>
  `rewind-${name}-${Int.toString(count)}.json`

let exportJson = (
  ~name: string,
  ~codec: codec<'msg>,
  t: RewindCore.t<'model, 'msg>,
): result<string, string> =>
  if RewindHistory.dropped(t.history) > 0 {
    Error(
      "exportJson: the history has dropped entries, so replaying this export would not match what actually ran",
    )
  } else {
    // messages only, oldest first, no init entry (msg: None marks it).
    let messages: array<JSON.t> = []
    RewindHistory.toArray(t.history)->Array.forEach(entry =>
      switch entry.msg {
      | Some(m) => messages->Array.push(codec.encode(m))
      | None => ()
      }
    )
    let json = JSON.Encode.object(
      Dict.fromArray([
        ("rewind", JSON.Encode.int(formatVersion)),
        ("name", JSON.Encode.string(name)),
        ("count", JSON.Encode.int(Array.length(messages))),
        ("messages", JSON.Encode.array(messages)),
      ]),
    )
    Ok(JSON.stringify(json, ~space=2))
  }

// Decodes `items` in order, stopping at the first failure. A `while` loop
// (not recursion) so an import with many messages can't blow the stack.
let decodeMessages = (codec: codec<'msg>, items: array<JSON.t>): result<array<'msg>, string> => {
  let count = Array.length(items)
  let decoded: array<'msg> = []
  let error = ref(None)
  let i = ref(0)
  while i.contents < count && error.contents == None {
    switch codec.decode(Array.getUnsafe(items, i.contents)) {
    | Ok(m) =>
      decoded->Array.push(m)
      i := i.contents + 1
    | Error(reason) =>
      error := Some(`importJson: message ${Int.toString(i.contents)}: ${reason}`)
    }
  }
  switch error.contents {
  | Some(e) => Error(e)
  | None => Ok(decoded)
  }
}

let importJson = (~codec: codec<'msg>, raw: string): result<array<'msg>, string> => {
  let parsed: result<JSON.t, string> = try {
    Ok(JSON.parseOrThrow(raw))
  } catch {
  | JsExn(_) => Error("importJson: not valid JSON")
  }
  switch parsed {
  | Error(e) => Error(e)
  | Ok(JSON.Object(dict)) =>
    switch Dict.get(dict, "rewind") {
    | Some(JSON.Number(v)) if v == Int.toFloat(formatVersion) =>
      switch Dict.get(dict, "messages") {
      | Some(JSON.Array(items)) => decodeMessages(codec, items)
      | _ => Error("importJson: \"messages\" is not an array")
      }
    | _ => Error("importJson: missing or unsupported \"rewind\" version")
    }
  | Ok(_) => Error("importJson: missing or unsupported \"rewind\" version")
  }
}
