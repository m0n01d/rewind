# rewind: design

## 1. Goal and the Elm features we copy

rewind is a time-travel debugger for ReScript React apps. It records each message and each model. A developer can then pause the running app and step through its history.

The design follows the debugger in `elm/browser`, version 1.0.2. We checked its source on 2026-09-25. rewind copies four of its features:

- a paused view of any past state
- a jump to any recorded state, by index
- an export and an import of a message log, as JSON
- a capped history, so a long session does not use unlimited memory

The first user of this library is reflip. See `~/code/reflip`.

## 2. The six rules, and where they differ from Elm

`RewindCore.update` follows six rules. We checked each one against `elm/browser`, version 1.0.2, file `src/Debugger/Main.elm`, on 2026-09-25.

1. **App.** The live model always advances. While recording, rewind also pushes a new entry to the history. When the cap drops old entries, a paused cursor still stays on the same entry. If the cap drops the paused entry itself, the cursor clamps to index 0. After that, each push still drops the oldest entry. The cursor then shows this new oldest entry each time.
2. **Jump.** rewind clamps the index to the valid range. The newest index gives the live view. Any other index pauses on that entry.
3. **Resume.** This action sets the cursor to live.
4. **Replace.** This action replays a list of messages from the start model. It builds a fresh, capped history. When the replay ends, the cursor is live.
5. **No recording.** App still advances the live model. Jump, Resume, and Replace do nothing.
6. **View.** A paused cursor shows the model of its entry. The live cursor shows the live model.

Rule 2 is the one deviation from Elm. In Elm, a jump to the newest state stays paused. In rewind, a jump to the newest state resumes the live view.

## 3. The effect rule: model and live

A React hook built on rewind must return two models. `model` is for the render. `live` is for effects, such as a network call in a `useEffect`.

This split matches Elm. Elm computes subscriptions from the newest model, not the paused one. In `elm/browser`, version 1.0.2, file `src/Debugger/Main.elm`, line 56, `wrapSubs` calls `getLatestModel`. We checked this on 2026-09-25.

An effect that reads a paused model can run its work again. reflip's upload effect is one example. A stale, paused model can fire a second upload of the same file.

Import writes to `live`, not only to the history. The panel's Import
control sends a `Replace` action. `Replace` rebuilds the history from the
imported messages, and it also rewrites `live` to the last one. A
live-reading effect runs again against this rebuilt state, the same as it
runs for any other message. We checked this in `RewindCore.res`, the
`Replace` branch of `update`, on 2026-09-25.

## 4. The reflection rule

rewind reads the shape of a value with the stdlib function `Type.Classify.classify`. We checked this against the installed `rescript` package on 2026-09-25.

The bindings in `src/RewindJs.res` follow one rule. Each binding checks the type of the value at runtime first. If the check passes, the binding returns a primitive value. If it does not, the binding returns an abstract type.

## 5. The UI we copy

A later commit adds a React panel. It copies six parts of Elm's debugger UI:

- a small badge in the corner, which shows the current message count
- a list of past messages, one row per recorded step
- three views for the selected entry: Model, Message, and Diff
- a full-screen blocker while paused, which blocks these events:
  - click
  - mousedown
  - mouseup
  - keydown
  - keyup
  - keypress
  - pointerdown
  - pointerup
  - touchstart
  - touchend
  - wheel
  - submit
  - input
- a click anywhere on the blocker, which resumes the live view
- Import and Export controls

When the app supplies a codec, rewind shows the Import and Export controls. Otherwise, it hides them.

We checked this list against `src/RewindPanel.res`, the `eventTypes` array in the blocker effect, on 2026-09-25.

## 6. Non-goals for v0

Version 0 of rewind does not cover five things:

- skip messages, to leave one recorded message out of a replay
- a command runtime, such as Elm's `Cmd`
- a publish of this package to npm
- state that survives a page reload
- printing for `Belt.Map` and similar tree-based collections

A later version can add any of these. None of them changes the design in this document.

## 7. Printing limits

ReScript compiles some types to the same runtime shape. Because of this, rewind's printer cannot always tell two values apart:

- `Some(x)` and `x` itself
- a nullary constructor, such as `Red`, and a plain string
- a tuple and an array
- `list{}`, the empty list, and the number `0`
- `unit` and `None`

We checked this against the compiled output of the `rescript` compiler on 2026-09-25. This is a limit of runtime reflection, not a bug rewind can fix. A precise codec, written by the app, does not have this problem.
