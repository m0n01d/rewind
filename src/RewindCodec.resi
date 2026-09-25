// JSON export/import for a codec-equipped app. See RewindCodec.res for why
// this only needs the stdlib JSON module.

/** A pair of pure functions for turning one app message into JSON and
    back. `decode` returns `Error(reason)` for a value it cannot read. */
type codec<'msg> = {
  encode: 'msg => JSON.t,
  decode: JSON.t => result<'msg, string>,
}

/** The file name for an export named `name` with `count` messages:
    `"rewind-<name>-<count>.json"`. */
let fileName: (~name: string, ~count: int) => string

/** Encodes the recorded messages (oldest first, no init entry) as
    `{"rewind":1,"name":…,"count":n,"messages":[…]}`.

    Returns `Error` when the history has already dropped entries at its
    cap: a replay of a partial history would not match what actually ran. */
let exportJson: (~name: string, ~codec: codec<'msg>, RewindCore.t<'model, 'msg>) => result<
  string,
  string,
>

/** Decodes a rewind export back into an array of messages, oldest first.

    Returns `Error` when: the string is not JSON; the `"rewind"` field is
    missing or is not the version this module writes; `"messages"` is not
    an array; or `codec.decode` fails on one message — the error then
    names its zero-based index and the decoder's own message. */
let importJson: (~codec: codec<'msg>, string) => result<array<'msg>, string>
