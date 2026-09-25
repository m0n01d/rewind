// The runtime around RewindCore: a mutable store a React hook can subscribe
// to with useSyncExternalStore, plus a type-erased `session` so the panel
// (which knows nothing about any one app's 'model/'msg) can drive any
// store through one shared shape. The erasure is closures only -- every
// session field is a function built while 'model/'msg are still in scope,
// so nothing here casts or claims a type a value may not have.

type t<'model, 'msg> = {
  mutable state: RewindCore.t<'model, 'msg>,
  mutable reduce: ('model, 'msg) => 'model,
  mutable listeners: array<unit => unit>,
  // Built once, in `make`, by closing over this very record -- see the
  // comment there. Marked `mutable` only so `make` can tie that knot;
  // nothing else ever reassigns it.
  mutable dispatch: 'msg => unit,
}

let send = (store: t<'model, 'msg>, action: RewindCore.msg<'msg>): unit => {
  store.state = RewindCore.update(~reduce=store.reduce, store.state, action)
  store.listeners->Array.forEach(listener => listener())
}

let make = (
  ~cap: int,
  ~recording: bool,
  ~reduce: ('model, 'msg) => 'model,
  model: 'model,
  time: float,
): t<'model, 'msg> => {
  let store = {
    state: RewindCore.init(~cap, ~recording, model, time),
    reduce,
    listeners: [],
    dispatch: (_: 'msg) => (),
  }
  // Tie the knot: `dispatch` closes over `store` itself, now that it
  // exists, so the function identity below never changes for this store's
  // lifetime -- callers can hand it to React without a useCallback.
  store.dispatch = msg => send(store, App(msg, Date.now()))
  store
}

let setReduce = (store: t<'model, 'msg>, reduce: ('model, 'msg) => 'model): unit =>
  store.reduce = reduce

let getSnapshot = (store: t<'model, 'msg>): RewindCore.t<'model, 'msg> => store.state

// Matches the shape `useSyncExternalStore` wants for its `subscribe`
// argument: `(onStoreChange) => unsubscribe`.
let subscribe = (store: t<'model, 'msg>, onChange: unit => unit): (unit => unit) => {
  store.listeners = Array.concat(store.listeners, [onChange])
  () => store.listeners = store.listeners->Array.filter(l => l !== onChange)
}

// --- the type-erased session the panel drives ------------------------------

type entrySnapshot = {msg: option<RewindValue.t>, model: RewindValue.t, time: float}

type snapshot = {
  count: int, // history length, init entry not counted
  cursor: option<int>, // None while Live, Some(i) while Paused(i)
  dropped: int,
  entry: int => option<entrySnapshot>,
}

type session = {
  id: int,
  mutable name: string,
  subscribe: (unit => unit) => (unit => unit),
  getSnapshot: unit => snapshot,
  jump: int => unit,
  resume: unit => unit,
  // `Some` only when the app passed `~codec` to `Rewind.use`.
  export: option<unit => result<string, string>>,
  import: option<string => result<unit, string>>,
}

let idCounter = ref(0)
let nextId = (): int => {
  idCounter := idCounter.contents + 1
  idCounter.contents
}

let buildSnapshot = (state: RewindCore.t<'model, 'msg>): snapshot => {
  let history = state.history
  {
    count: RewindHistory.length(history) - 1,
    cursor: switch state.cursor {
    | Live => None
    | Paused(i) => Some(i)
    },
    dropped: RewindHistory.dropped(history),
    entry: i =>
      switch RewindHistory.get(history, i) {
      | None => None
      | Some(e) =>
        Some({
          msg: switch e.msg {
          | None => None
          | Some(m) => Some(RewindValue.make(m))
          },
          model: RewindValue.make(e.model),
          time: e.time,
        })
      },
  }
}

// `name` is the app's own, pre-collision name ("app"); RewindRegistry.add
// may rename the session (mutating `.name`) if another session already
// holds that name. `export`'s filename intentionally uses this closure's
// own `name`, fixed at creation -- a rename only changes what the panel
// displays, not an in-flight export's file name.
// The trailing `()` is required: an optional labeled argument with nothing
// positional after it is ambiguous between "still waiting for ~codec" and
// "done, use the default" -- the unit arg is the standard resolution.
let makeSession = (
  ~name: string,
  ~store: t<'model, 'msg>,
  ~codec: option<RewindCodec.codec<'msg>>=?,
  (),
): session => {
  // Caches the last (state, snapshot) pair so getSnapshot returns the same
  // object while store.state hasn't changed -- required for
  // useSyncExternalStore, which else re-renders forever (Object.is on a
  // freshly-built record is never true).
  let cache: ref<option<(RewindCore.t<'model, 'msg>, snapshot)>> = ref(None)
  let getSnapshot = (): snapshot =>
    switch cache.contents {
    | Some(cachedState, snap) if cachedState === store.state => snap
    | _ =>
      let snap = buildSnapshot(store.state)
      cache := Some((store.state, snap))
      snap
    }
  {
    id: nextId(),
    name,
    subscribe: onChange => subscribe(store, onChange),
    getSnapshot,
    jump: i => send(store, Jump(i)),
    resume: () => send(store, Resume),
    export: switch codec {
    | None => None
    | Some(c) => Some(() => RewindCodec.exportJson(~name, ~codec=c, store.state))
    },
    import: switch codec {
    | None => None
    | Some(c) =>
      Some(
        raw =>
          switch RewindCodec.importJson(~codec=c, raw) {
          | Error(e) => Error(e)
          | Ok(msgs) =>
            send(store, Replace(msgs, Date.now()))
            Ok()
          },
      )
    },
  }
}
