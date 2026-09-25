open RewindPanelState

let kit = TestKit.make()

// --- initial ---------------------------------------------------------------
TestKit.check(kit, "initial: closed", initial.open_ == false)
TestKit.check(kit, "initial: no session selected", initial.selectedSessionId == None)
TestKit.check(kit, "initial: tab is Model", initial.tab == Model)
TestKit.check(kit, "initial: expanded is empty", initial.expanded == [])
TestKit.check(kit, "initial: no error", initial.error == None)

// --- Open / Close ------------------------------------------------------------
let m1 = update(initial, Open)
TestKit.check(kit, "Open: open_ becomes true", m1.open_ == true)
let m2 = update(m1, Close)
TestKit.check(kit, "Close: open_ becomes false", m2.open_ == false)

// --- SelectSession -------------------------------------------------------------
let m3 = update(initial, SelectSession(7))
TestKit.check(kit, "SelectSession: sets the id", m3.selectedSessionId == Some(7))
let m4 = update(m3, SelectSession(9))
TestKit.check(kit, "SelectSession: a later call replaces the id", m4.selectedSessionId == Some(9))

// --- SelectTab -------------------------------------------------------------
TestKit.check(
  kit,
  "SelectTab(Message): tab becomes Message",
  update(initial, SelectTab(Message)).tab == Message,
)
TestKit.check(kit, "SelectTab(Diff): tab becomes Diff", update(initial, SelectTab(Diff)).tab == Diff)

// --- ToggleExpanded ----------------------------------------------------------
let m5 = update(initial, ToggleExpanded("todos[0]"))
TestKit.check(kit, "ToggleExpanded: adds an unexpanded path", m5.expanded == ["todos[0]"])
let m6 = update(m5, ToggleExpanded("todos[1]"))
TestKit.check(
  kit,
  "ToggleExpanded: a second path is appended",
  m6.expanded == ["todos[0]", "todos[1]"],
)
let m7 = update(m6, ToggleExpanded("todos[0]"))
TestKit.check(kit, "ToggleExpanded: toggling an expanded path removes it", m7.expanded == ["todos[1]"])

// --- ShowError / ClearError ----------------------------------------------------
let m8 = update(initial, ShowError("bad json"))
TestKit.check(kit, "ShowError: sets the error", m8.error == Some("bad json"))
let m9 = update(m8, ShowError("second failure"))
TestKit.check(kit, "ShowError: a later error replaces the first", m9.error == Some("second failure"))
let m10 = update(m9, ClearError)
TestKit.check(kit, "ClearError: clears the error", m10.error == None)

// --- update only ever touches the field its own message names ----------------
let full: model = {
  open_: true,
  selectedSessionId: Some(3),
  tab: Diff,
  expanded: ["a"],
  error: Some("e"),
}
let afterTabChange = update(full, SelectTab(Message))
TestKit.check(
  kit,
  "SelectTab: leaves open_/selectedSessionId/expanded/error untouched",
  afterTabChange.open_ == true &&
    afterTabChange.selectedSessionId == Some(3) &&
    afterTabChange.expanded == ["a"] &&
    afterTabChange.error == Some("e"),
)

TestKit.finish(kit, "RewindPanelStateTest")
