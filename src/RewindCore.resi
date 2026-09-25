// The pure debugger state machine. Semantics checked against elm/browser
// 1.0.2 src/Debugger/Main.elm on 2026-09-25.

/** One recorded step. `msg: None` marks the init entry — the model
    before any app message ran. */
type entry<'model, 'msg> = {
  msg: option<'msg>,
  model: 'model,
  time: float,
}

/** `Live` follows the newest state as it happens. `Paused(i)` views a
    fixed entry (index `i` into the history, oldest-first) while `live`
    keeps advancing underneath it. */
type cursor = Live | Paused(int)

type t<'model, 'msg> = {
  initial: 'model,
  live: 'model,
  history: RewindHistory.t<entry<'model, 'msg>>,
  cursor: cursor,
  recording: bool,
}

/** An action on the debugger.
    - `App(m, time)`: the wrapped app dispatched message `m`.
    - `Jump(i)`: view history entry `i`.
    - `Resume`: go back to `Live`.
    - `Replace(msgs, time)`: replace the whole history with a replay of
      `msgs` from `initial` (an import). */
type msg<'msg> = App('msg, float) | Jump(int) | Resume | Replace(array<'msg>, float)

/** Starts a debugger at `model`, timestamped `time`, holding at most
    `cap` history entries. `recording=false` makes `update` only ever
    advance `live` — see rule 5 on `update`. */
let init: (~cap: int, ~recording: bool, 'model, float) => t<'model, 'msg>

/** Applies one `msg<'msg>` action. `reduce` is the wrapped app's own
    update function.

    1. `App(m, time)`: `live` always advances (`reduce(live, m)`), and
       recording pushes `{msg: Some(m), model: live', time}`. `Live` stays
       `Live`. A `Paused(i)` cursor stays on the *same entry*: if the push
       dropped `k` entries to stay at cap, the cursor becomes
       `Paused(max(0, i - k))`.
    2. `Jump(i)`: clamps `i` to `[0, length - 1]`. The newest index gives
       `Live`; any other index gives `Paused(i)`. **Deliberate deviation
       from Elm**: elm/browser's `Main.elm` stays paused even on the
       newest entry — jumping to the end here instead resumes live.
    3. `Resume`: gives `Live`.
    4. `Replace(msgs, time)`: replays `msgs` from `initial` through
       `reduce` into a fresh history (the init entry, then one entry per
       message, all timestamped `time`; the existing cap still applies).
       `live` becomes the last model, and the cursor becomes `Live`.
    5. `recording=false`: `App` only advances `live`, and leaves history
       and cursor untouched. `Jump`, `Resume` and `Replace` do nothing at
       all. */
let update: (~reduce: ('model, 'msg) => 'model, t<'model, 'msg>, msg<'msg>) => t<'model, 'msg>

/** 6. The model to render: the entry at `Paused(i)`, or `live` when
    `Live`. */
let view: t<'model, 'msg> => 'model

/** `true` for any `Paused` cursor, `false` for `Live`. */
let isPaused: t<'model, 'msg> => bool
