// The pure debugger state machine. Semantics checked against elm/browser
// 1.0.2 src/Debugger/Main.elm on 2026-09-25 — see RewindCore.resi for the
// numbered rules and the one deliberate deviation (Jump).

type entry<'model, 'msg> = {
  msg: option<'msg>, // None marks the init entry.
  model: 'model,
  time: float,
}

type cursor = Live | Paused(int)

type t<'model, 'msg> = {
  initial: 'model,
  live: 'model,
  history: RewindHistory.t<entry<'model, 'msg>>,
  cursor: cursor,
  recording: bool,
}

type msg<'msg> = App('msg, float) | Jump(int) | Resume | Replace(array<'msg>, float)

let init = (~cap: int, ~recording: bool, model: 'model, time: float): t<'model, 'msg> => {
  initial: model,
  live: model,
  history: RewindHistory.make(~cap, {msg: None, model, time}),
  cursor: Live,
  recording,
}

let update = (
  ~reduce: ('model, 'msg) => 'model,
  t: t<'model, 'msg>,
  action: msg<'msg>,
): t<'model, 'msg> =>
  switch action {
  | App(m, time) =>
    // live always advances, recording or not (rule 1, rule 5).
    let live = reduce(t.live, m)
    if t.recording {
      let droppedBefore = RewindHistory.dropped(t.history)
      let history = RewindHistory.push(t.history, {msg: Some(m), model: live, time})
      let droppedByThisPush = RewindHistory.dropped(history) - droppedBefore
      let cursor = switch t.cursor {
      | Live => Live
      | Paused(i) => Paused(Int.clamp(~min=0, i - droppedByThisPush))
      }
      {...t, live, history, cursor}
    } else {
      {...t, live}
    }
  | Jump(i) =>
    if t.recording {
      let lastIndex = RewindHistory.length(t.history) - 1
      let clamped = Int.clamp(~min=0, ~max=lastIndex, i)
      {...t, cursor: clamped == lastIndex ? Live : Paused(clamped)}
    } else {
      t
    }
  | Resume => t.recording ? {...t, cursor: Live} : t
  | Replace(msgs, time) =>
    if t.recording {
      let cap = RewindHistory.cap(t.history)
      let live = ref(t.initial)
      let history = ref(RewindHistory.make(~cap, {msg: None, model: t.initial, time}))
      Array.forEach(msgs, m => {
        let next = reduce(live.contents, m)
        live := next
        history := RewindHistory.push(history.contents, {msg: Some(m), model: next, time})
      })
      {...t, live: live.contents, history: history.contents, cursor: Live}
    } else {
      t
    }
  }

let view = (t: t<'model, 'msg>): 'model =>
  switch t.cursor {
  | Live => t.live
  | Paused(i) => {
      let entry = RewindHistory.get(t.history, i)->Option.getOrThrow(
        ~message="RewindCore.view: Paused cursor index is out of range",
      )
      entry.model
    }
  }

let isPaused = (t: t<'model, 'msg>): bool =>
  switch t.cursor {
  | Live => false
  | Paused(_) => true
  }
