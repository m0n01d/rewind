// Pure UI state for the panel: open/closed, which session and tab are
// selected, which Model/Diff tree nodes are expanded, and the last
// Export/Import error. No I/O -- RewindPanel.res is the only place that
// reads or writes this, through React.useReducer.

type tab = Model | Message | Diff

type model = {
  open_: bool,
  selectedSessionId: option<int>,
  tab: tab,
  expanded: array<string>, // Model/Diff tree node paths, toggled open
  error: option<string>, // last Export or Import failure, either one
}

type msg =
  | Open
  | Close
  | SelectSession(int)
  | SelectTab(tab)
  | ToggleExpanded(string)
  | ShowError(string)
  | ClearError

let initial: model = {
  open_: false,
  selectedSessionId: None,
  tab: Model,
  expanded: [],
  error: None,
}

let update = (model: model, msg: msg): model =>
  switch msg {
  | Open => {...model, open_: true}
  | Close => {...model, open_: false}
  | SelectSession(id) => {...model, selectedSessionId: Some(id)}
  | SelectTab(tab) => {...model, tab}
  | ToggleExpanded(path) =>
    let expanded = if model.expanded->Array.includes(path) {
      model.expanded->Array.filter(p => p != path)
    } else {
      Array.concat(model.expanded, [path])
    }
    {...model, expanded}
  | ShowError(reason) => {...model, error: Some(reason)}
  | ClearError => {...model, error: None}
  }
