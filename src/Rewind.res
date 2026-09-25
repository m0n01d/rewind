// See Rewind.resi for the public contract this implements.

// Not in @rescript/react 0.15 -- hand-bound here, matching the honest-FFI
// rule: this is exactly React's own signature, no cast involved.
@module("react")
external useSyncExternalStore: (
  (unit => unit) => (unit => unit),
  unit => 'snapshot,
) => 'snapshot = "useSyncExternalStore"

type codec<'msg> = RewindCodec.codec<'msg>

type t<'model, 'msg> = {
  model: 'model,
  live: 'model,
  dispatch: 'msg => unit,
  paused: bool,
}

let use = (
  ~name: option<string>=?,
  ~codec: option<RewindCodec.codec<'msg>>=?,
  ~cap: option<int>=?,
  ~enabled: option<bool>=?,
  reduce: ('model, 'msg) => 'model,
  initialModel: 'model,
): t<'model, 'msg> => {
  let name = switch name {
  | Some(n) => n
  | None => "app"
  }
  let cap = switch cap {
  | Some(c) => c
  | None => 10000
  }
  let enabled = switch enabled {
  | Some(e) => e
  | None => true
  }

  // Built once per component instance -- useState's initializer only ever
  // runs on mount, so this store (and its stable `dispatch`) survives every
  // later render.
  let (store, _setStore) = React.useState(() =>
    RewindStore.make(~cap, ~recording=enabled, ~reduce, initialModel, Date.now())
  )
  // `reduce` itself can be a fresh closure each render (it closes over
  // props/state); keep the store's copy current so App messages replay
  // against the latest logic.
  RewindStore.setReduce(store, reduce)

  let coreState = useSyncExternalStore(
    onChange => RewindStore.subscribe(store, onChange),
    () => RewindStore.getSnapshot(store),
  )

  React.useEffect0(() => {
    if enabled {
      let session = RewindStore.makeSession(~name, ~store, ~codec?, ())
      RewindRegistry.add(session)
      RewindPanel.ensureMounted()
      Some(() => RewindRegistry.remove(session))
    } else {
      None
    }
  })

  {
    model: RewindCore.view(coreState),
    live: coreState.live,
    dispatch: store.dispatch,
    paused: RewindCore.isPaused(coreState),
  }
}

let useReducer = (
  ~name: option<string>=?,
  ~codec: option<RewindCodec.codec<'msg>>=?,
  ~cap: option<int>=?,
  ~enabled: option<bool>=?,
  reduce: ('model, 'msg) => 'model,
  initialModel: 'model,
): ('model, 'msg => unit) => {
  let result = use(~name?, ~codec?, ~cap?, ~enabled?, reduce, initialModel)
  (result.model, result.dispatch)
}
