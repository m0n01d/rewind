// The public API. See DESIGN.md for the model/live split (§3) and the
// six update rules it wraps (§2).

/** A pair of pure functions for turning one app message into JSON and back
    -- pass one to record an export/import-capable session. */
type codec<'msg> = RewindCodec.codec<'msg>

type t<'model, 'msg> = {
  /** What to render: the paused entry's model, or the live model when not
      paused. */
  model: 'model,
  /** The live model, for an effect that must not repeat itself against a
      paused, stale view -- see DESIGN.md §3. */
  live: 'model,
  /** Stable across renders: dispatches an app message through the
      debugger and into `reduce`. */
  dispatch: 'msg => unit,
  /** `true` while a past entry is being viewed. */
  paused: bool,
}

/** Runs `reduce` as a TEA update function, recording each message so the
    panel can step through history. `~name` defaults to `"app"`, `~cap` to
    `10000`, `~enabled` to `true`.

    `~enabled=false` turns off recording entirely: `live` still advances on
    every message, but no history is kept, no session is registered, and
    the panel never mounts for this hook.

    Pass `~codec` to let the panel export and import this session's
    message log as JSON; without one, Export/Import stay hidden. */
let use: (
  ~name: string=?,
  ~codec: codec<'msg>=?,
  ~cap: int=?,
  ~enabled: bool=?,
  ('model, 'msg) => 'model,
  'model,
) => t<'model, 'msg>

/** A drop-in for `React.useReducer`, for a component whose effects never
    need the live/model split `use` offers -- it reads `model` for both,
    the same tradeoff `React.useReducer` itself already has. Same
    arguments as `use`. */
let useReducer: (
  ~name: string=?,
  ~codec: codec<'msg>=?,
  ~cap: int=?,
  ~enabled: bool=?,
  ('model, 'msg) => 'model,
  'model,
) => ('model, 'msg => unit)
