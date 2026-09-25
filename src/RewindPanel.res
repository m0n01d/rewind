// The panel's own React tree, mounted once into an isolated shadow root
// (see ensureMounted below) so its styles can't leak into, or be leaked
// by, the host page. See DESIGN.md §5 for the six parts of elm/browser's
// debugger UI this copies, and HANDOFF.md's "Step 4 design" for the
// index-space and reactivity notes this file follows.

// Not in @rescript/react 0.15 -- hand-bound here. Same honest-FFI
// signature as Rewind.res's own copy; each module binds it itself,
// matching this codebase's per-module binding style.
@module("react")
external useSyncExternalStore: (
  (unit => unit) => (unit => unit),
  unit => 'snapshot,
) => 'snapshot = "useSyncExternalStore"

// --- pure helpers ------------------------------------------------------

// Row label for the message list. `msg = None` marks the init entry --
// RewindCore.resi's own contract -- and that stays the right check even
// after the cap has dropped entries: once the true Init entry is itself
// dropped, index 0 is just the oldest-retained real message, and must
// show that message, not a stale "Init". Checking `msg` instead of the
// row's index handles both cases with one rule.
let rowLabel = (entry: RewindStore.entrySnapshot): string =>
  switch entry.msg {
  | Some(m) => RewindValue.msgSummary(m)
  | None => "Init"
  }

// The index whose Model/Message/Diff tab should show: the paused cursor,
// or the latest entry (`count`) when live. `count` is 0 (Init) when no
// messages have been recorded yet -- see HANDOFF.md's index-space note.
let selectedIndex = (snapshot: RewindStore.snapshot): int =>
  switch snapshot.cursor {
  | Some(i) => i
  | None => snapshot.count
  }

// A Model/Message tree node. `path` is a UI-only expand/collapse key --
// independent of RewindValue.diff's own path strings, which are only
// ever displayed, never used as a React/state key.
let rec renderNode = (
  ~path: string,
  ~label: string,
  ~value: RewindValue.t,
  ~expanded: array<string>,
  ~panelDispatch: RewindPanelState.msg => unit,
): React.element =>
  if RewindValue.isLeaf(value) {
    <div className="rewind-tree-leaf" key=path>
      <span className="rewind-tree-label"> {React.string(label)} </span>
      <span className="rewind-tree-value"> {React.string(RewindValue.summary(value))} </span>
    </div>
  } else {
    let isOpen = expanded->Array.includes(path)
    <div className="rewind-tree-node" key=path>
      <div
        className="rewind-tree-row"
        onClick={_ => panelDispatch(RewindPanelState.ToggleExpanded(path))}>
        <span className="rewind-tree-caret"> {React.string(isOpen ? "▾" : "▸")} </span>
        <span className="rewind-tree-label"> {React.string(label)} </span>
        {isOpen
          ? React.null
          : <span className="rewind-tree-value"> {React.string(RewindValue.summary(value))} </span>}
      </div>
      {isOpen
        ? <div className="rewind-tree-children">
            {value
            ->RewindValue.children
            ->Array.map(((childLabel, childValue)) =>
              renderNode(
                ~path={path ++ "/" ++ childLabel},
                ~label=childLabel,
                ~value=childValue,
                ~expanded,
                ~panelDispatch,
              )
            )
            ->React.array}
          </div>
        : React.null}
    </div>
  }

let renderDiff = (changes: array<RewindValue.change>): React.element =>
  if Array.length(changes) == 0 {
    <div className="rewind-diff-empty"> {React.string("No changes.")} </div>
  } else {
    changes
    ->Array.map(c => {
      let before = switch c.before {
      | Some(s) => s
      | None => "—"
      }
      let after = switch c.after {
      | Some(s) => s
      | None => "—"
      }
      let label = c.path == "" ? "(root)" : c.path
      <div className="rewind-diff-row" key={c.path}>
        {React.string(`${label}: ${before} → ${after}`)}
      </div>
    })
    ->React.array
  }

// --- export / import -----------------------------------------------------

let handleExport = (session: RewindStore.session, panelDispatch: RewindPanelState.msg => unit): unit =>
  switch session.export {
  | None => ()
  | Some(export) =>
    switch export() {
    | Error(reason) => panelDispatch(RewindPanelState.ShowError(reason))
    | Ok(json) =>
      let blob = RewindDom.makeBlob([json], {type_: "application/json"})
      let url = RewindDom.createObjectURL(blob)
      let a = RewindDom.createElement("a")
      RewindDom.setAttribute(a, "href", url)
      RewindDom.setAttribute(
        a,
        "download",
        RewindCodec.fileName(~name=session.name, ~count=session.getSnapshot().count),
      )
      RewindDom.appendChild(RewindDom.body, a)
      RewindDom.click(a)
      RewindDom.remove(a)
      RewindDom.revokeObjectURL(url)
    }
  }

let handleImportFile = async (
  session: RewindStore.session,
  panelDispatch: RewindPanelState.msg => unit,
  file: RewindDom.file,
): unit =>
  switch session.import {
  | None => ()
  | Some(doImport) =>
    let raw = await RewindDom.text(file)
    switch doImport(raw) {
    | Ok () => panelDispatch(RewindPanelState.ClearError)
    | Error(reason) => panelDispatch(RewindPanelState.ShowError(reason))
    }
  }

// --- components ----------------------------------------------------------

module SessionPicker = {
  @react.component
  let make = (
    ~sessions: array<RewindStore.session>,
    ~selectedId: option<int>,
    ~panelDispatch: RewindPanelState.msg => unit,
  ) =>
    <div className="rewind-session-picker">
      {sessions
      ->Array.map(s => {
        let isSelected = selectedId == Some(s.id)
        <button
          className={isSelected
            ? "rewind-session-btn rewind-session-btn-selected"
            : "rewind-session-btn"}
          key={Int.toString(s.id)}
          onClick={_ => panelDispatch(RewindPanelState.SelectSession(s.id))}>
          {React.string(s.name)}
        </button>
      })
      ->React.array}
    </div>
}

module SessionDetail = {
  @react.component
  let make = (
    ~session: RewindStore.session,
    ~panelState: RewindPanelState.model,
    ~panelDispatch: RewindPanelState.msg => unit,
  ) => {
    let snapshot = useSyncExternalStore(session.subscribe, session.getSnapshot)
    let importInputRef = React.useRef(Nullable.null)
    let selected = selectedIndex(snapshot)
    let selectedEntry = snapshot.entry(selected)
    let prevEntry = selected > 0 ? snapshot.entry(selected - 1) : None

    let onKeyDown = (event: ReactEvent.Keyboard.t) =>
      switch ReactEvent.Keyboard.key(event) {
      | "ArrowUp" =>
        ReactEvent.Keyboard.preventDefault(event)
        session.jump(selected > 0 ? selected - 1 : 0)
      | "ArrowDown" =>
        ReactEvent.Keyboard.preventDefault(event)
        if selected >= snapshot.count {
          session.resume()
        } else {
          session.jump(selected + 1)
        }
      | "Escape" =>
        ReactEvent.Keyboard.preventDefault(event)
        session.resume()
      | _ => ()
      }

    let rec rows = (i: int): array<React.element> =>
      if i > snapshot.count {
        []
      } else {
        let row = switch snapshot.entry(i) {
        | None => React.null
        | Some(entry) =>
          <div
            className={selected == i ? "rewind-row rewind-row-selected" : "rewind-row"}
            key={Int.toString(i)}
            onClick={_ => session.jump(i)}>
            <span className="rewind-row-index"> {React.string(`#${Int.toString(i)}`)} </span>
            <span className="rewind-row-label"> {React.string(rowLabel(entry))} </span>
          </div>
        }
        Array.concat([row], rows(i + 1))
      }

    <div className="rewind-session-detail">
      <div className="rewind-message-list" onKeyDown tabIndex={0}> {rows(0)->React.array} </div>
      <div className="rewind-tabs">
        <button
          className={panelState.tab == RewindPanelState.Model
            ? "rewind-tab rewind-tab-selected"
            : "rewind-tab"}
          onClick={_ => panelDispatch(RewindPanelState.SelectTab(RewindPanelState.Model))}>
          {React.string("Model")}
        </button>
        <button
          className={panelState.tab == RewindPanelState.Message
            ? "rewind-tab rewind-tab-selected"
            : "rewind-tab"}
          onClick={_ => panelDispatch(RewindPanelState.SelectTab(RewindPanelState.Message))}>
          {React.string("Message")}
        </button>
        <button
          className={panelState.tab == RewindPanelState.Diff
            ? "rewind-tab rewind-tab-selected"
            : "rewind-tab"}
          onClick={_ => panelDispatch(RewindPanelState.SelectTab(RewindPanelState.Diff))}>
          {React.string("Diff")}
        </button>
      </div>
      <div className="rewind-tab-content">
        {switch panelState.tab {
        | RewindPanelState.Model =>
          switch selectedEntry {
          | None => <div className="rewind-empty"> {React.string("No entry selected.")} </div>
          | Some(entry) =>
            renderNode(
              ~path="",
              ~label="model",
              ~value=entry.model,
              ~expanded=panelState.expanded,
              ~panelDispatch,
            )
          }
        | RewindPanelState.Message =>
          switch selectedEntry {
          | None => <div className="rewind-empty"> {React.string("No entry selected.")} </div>
          | Some({msg: None}) => <div className="rewind-empty"> {React.string("Init — no message.")} </div>
          | Some({msg: Some(m)}) =>
            renderNode(~path="", ~label="message", ~value=m, ~expanded=panelState.expanded, ~panelDispatch)
          }
        | RewindPanelState.Diff =>
          switch (prevEntry, selectedEntry) {
          | (Some(prev), Some(cur)) => renderDiff(RewindValue.diff(prev.model, cur.model))
          | _ =>
            <div className="rewind-diff-empty"> {React.string("No previous entry to diff against.")} </div>
          }
        }}
      </div>
      {switch (session.export, session.import) {
      | (None, None) => React.null
      | _ =>
        <div className="rewind-import-export">
          {switch session.export {
          | None => React.null
          | Some(_) =>
            <button className="rewind-btn" onClick={_ => handleExport(session, panelDispatch)}>
              {React.string("Export")}
            </button>
          }}
          {switch session.import {
          | None => React.null
          | Some(_) =>
            <div className="rewind-import-group">
              <input
                accept="application/json"
                className="rewind-hidden-input"
                onChange={event => {
                  let target: {"files": RewindDom.fileList} = ReactEvent.Form.target(event)
                  switch RewindDom.item(target["files"], 0) {
                  | None => ()
                  | Some(file) => handleImportFile(session, panelDispatch, file)->ignore
                  }
                }}
                ref={ReactDOM.Ref.domRef(importInputRef)}
                type_="file"
              />
              <button
                className="rewind-btn"
                onClick={_ =>
                  switch importInputRef.current->Nullable.toOption {
                  | Some(el) => RewindDom.click(el)
                  | None => ()
                  }}>
                {React.string("Import")}
              </button>
            </div>
          }}
        </div>
      }}
      {switch panelState.error {
      | None => React.null
      | Some(reason) =>
        <div className="rewind-error">
          {React.string(reason)}
          <button className="rewind-error-dismiss" onClick={_ => panelDispatch(RewindPanelState.ClearError)}>
            {React.string("×")}
          </button>
        </div>
      }}
    </div>
  }
}

module App = {
  @react.component
  let make = () => {
    let sessions = useSyncExternalStore(RewindRegistry.subscribe, RewindRegistry.getSnapshot)
    let anyPaused = useSyncExternalStore(onChange => {
      let unsubs = sessions->Array.map(s => s.subscribe(onChange))
      () => unsubs->Array.forEach(u => u())
    }, () => RewindRegistry.anyPaused())
    let (panelState, panelDispatch) = React.useReducer(RewindPanelState.update, RewindPanelState.initial)
    let rootRef = React.useRef(Nullable.null)

    // The full-screen blocker's window-capture side: only active while
    // paused. Anything whose composedPath runs through our own root
    // element is a click inside the panel itself (the blocker's own
    // "click to resume", or any panel control) and is left alone;
    // anything else targets the host app and gets stopped, at capture
    // time, before the app's own listeners see it.
    React.useEffect1(() => {
      if anyPaused {
        let eventTypes = [
          "click",
          "mousedown",
          "mouseup",
          "keydown",
          "keyup",
          "keypress",
          "pointerdown",
          "pointerup",
          "touchstart",
          "touchend",
          "wheel",
          "submit",
          "input",
        ]
        let handler = (event: Dom.event) =>
          switch rootRef.current->Nullable.toOption {
          | None => ()
          | Some(root) =>
            if !(RewindDom.composedPath(event)->RewindDom.includesEventTarget(root)) {
              RewindDom.stopPropagation(event)
              RewindDom.preventDefault(event)
            }
          }
        eventTypes->Array.forEach(t => RewindDom.addEventListener(RewindDom.window, t, handler, {capture: true}))
        Some(
          () =>
            eventTypes->Array.forEach(t =>
              RewindDom.removeEventListener(RewindDom.window, t, handler, {capture: true})
            ),
        )
      } else {
        None
      }
    }, [anyPaused])

    let selected = switch panelState.selectedSessionId {
    | Some(id) =>
      switch sessions->Array.find(s => s.id == id) {
      | Some(s) => Some(s)
      | None => sessions[0]
      }
    | None => sessions[0]
    }
    let selectedId = switch selected {
    | Some(s) => Some(s.id)
    | None => None
    }
    let badgeCount = switch selected {
    | Some(s) => s.getSnapshot().count
    | None => 0
    }

    <div className="rewind-root" ref={ReactDOM.Ref.domRef(rootRef)}>
      <button
        className="rewind-badge"
        onClick={_ => panelDispatch(panelState.open_ ? RewindPanelState.Close : RewindPanelState.Open)}>
        {React.string(`⏪ ${Int.toString(badgeCount)}`)}
      </button>
      {panelState.open_
        ? <div className="rewind-panel">
            {Array.length(sessions) > 1
              ? <SessionPicker panelDispatch selectedId sessions />
              : React.null}
            {switch selected {
            | Some(session) =>
              <SessionDetail key={Int.toString(session.id)} panelDispatch panelState session />
            | None => <div className="rewind-empty"> {React.string("No sessions recording.")} </div>
            }}
          </div>
        : React.null}
      {anyPaused
        ? <div className="rewind-blocker" onClick={_ => sessions->Array.forEach(s => s.resume())}>
            <div className="rewind-blocker-label"> {React.string("Click to resume")} </div>
          </div>
        : React.null}
    </div>
  }
}

// --- mount shell -----------------------------------------------------------

let panelCss = `
:host { all: initial; }
* { box-sizing: border-box; }
.rewind-root {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  font-size: 13px;
  color: #e6e6e6;
}
.rewind-badge {
  position: fixed;
  right: 12px;
  bottom: 12px;
  z-index: 2147483000;
  padding: 6px 10px;
  border: 1px solid #555;
  border-radius: 999px;
  background: #222;
  color: #e6e6e6;
  cursor: pointer;
  font: inherit;
}
.rewind-panel {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  width: 380px;
  max-width: 100vw;
  z-index: 2147483000;
  background: #1b1b1b;
  border-left: 1px solid #444;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
@media (max-width: 600px) {
  .rewind-panel {
    top: auto;
    left: 0;
    right: 0;
    width: auto;
    height: 60vh;
    border-left: none;
    border-top: 1px solid #444;
    border-radius: 10px 10px 0 0;
  }
}
.rewind-session-picker {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  padding: 8px;
  border-bottom: 1px solid #333;
}
.rewind-session-btn {
  padding: 3px 8px;
  border: 1px solid #555;
  border-radius: 4px;
  background: #262626;
  color: #ccc;
  cursor: pointer;
  font: inherit;
}
.rewind-session-btn-selected { background: #3a5a8a; color: #fff; border-color: #5a82c2; }
.rewind-session-detail {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}
.rewind-message-list {
  flex: 1;
  min-height: 60px;
  overflow-y: auto;
  border-bottom: 1px solid #333;
}
.rewind-row {
  display: flex;
  gap: 8px;
  padding: 4px 8px;
  cursor: pointer;
  border-bottom: 1px solid #262626;
}
.rewind-row:hover { background: #262626; }
.rewind-row-selected { background: #3a5a8a; color: #fff; }
.rewind-row-index { color: #888; font-family: ui-monospace, monospace; }
.rewind-row-selected .rewind-row-index { color: #cddcf5; }
.rewind-tabs { display: flex; border-bottom: 1px solid #333; }
.rewind-tab {
  flex: 1;
  padding: 6px 4px;
  border: none;
  background: none;
  color: #aaa;
  cursor: pointer;
  font: inherit;
  border-bottom: 2px solid transparent;
}
.rewind-tab-selected { color: #fff; border-bottom-color: #5a82c2; }
.rewind-tab-content { flex: 1; min-height: 60px; overflow: auto; padding: 8px; }
.rewind-empty, .rewind-diff-empty { color: #888; padding: 4px 0; }
.rewind-tree-node, .rewind-tree-leaf { font-family: ui-monospace, monospace; }
.rewind-tree-row { display: flex; gap: 6px; cursor: pointer; padding: 2px 0; }
.rewind-tree-leaf { display: flex; gap: 6px; padding: 2px 0; }
.rewind-tree-caret { width: 10px; color: #888; }
.rewind-tree-label { color: #7fb1e3; }
.rewind-tree-value { color: #ddd; overflow-wrap: anywhere; }
.rewind-tree-children { padding-left: 14px; border-left: 1px solid #383838; margin-left: 4px; }
.rewind-diff-row { font-family: ui-monospace, monospace; padding: 2px 0; overflow-wrap: anywhere; }
.rewind-import-export { display: flex; gap: 6px; padding: 8px; border-top: 1px solid #333; }
.rewind-import-group { display: inline-flex; }
.rewind-btn {
  padding: 4px 10px;
  border: 1px solid #555;
  border-radius: 4px;
  background: #262626;
  color: #e6e6e6;
  cursor: pointer;
  font: inherit;
}
.rewind-hidden-input { display: none; }
.rewind-error {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 8px;
  background: #4a1f1f;
  color: #ffb4b4;
  border-top: 1px solid #6a2b2b;
}
.rewind-error-dismiss {
  margin-left: auto;
  border: none;
  background: none;
  color: inherit;
  cursor: pointer;
  font: inherit;
}
.rewind-blocker {
  position: fixed;
  inset: 0;
  z-index: 2147482900;
  background: rgba(0, 0, 0, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}
.rewind-blocker-label {
  padding: 8px 16px;
  border-radius: 6px;
  background: #222;
  color: #fff;
  border: 1px solid #555;
}
`

let mounted = ref(false)

let ensureMounted = (): unit =>
  if !mounted.contents {
    mounted.contents = true
    let host = RewindDom.createElement("div")
    RewindDom.appendChild(RewindDom.body, host)
    let shadow = RewindDom.attachShadow(host, {mode: "open"})
    let style = RewindDom.createElement("style")
    RewindDom.setTextContent(style, panelCss)
    RewindDom.shadowAppendChild(shadow, style)
    let mountPoint = RewindDom.createElement("div")
    RewindDom.shadowAppendChild(shadow, mountPoint)
    let root = ReactDOM.Client.createRoot(mountPoint)
    ReactDOM.Client.Root.render(root, <App />)
  }
