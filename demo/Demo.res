// The rewind demo app: a counter plus a todo list, wired through
// Rewind.use so the panel (built on the `panel` branch) can record and
// step through its history.
//
// This file exists to demonstrate the model/live split from DESIGN.md
// §3: the Save effect below reads only `rewind.live` (so a paused,
// stale view can never re-fire the timer), and the view below renders
// only `rewind.model` (so a paused view shows the paused entry, not the
// live one).

type todo = {
  text: string,
  // `done` is a reserved word in ReScript's grammar; JsxDOM itself hits
  // the same problem with `type` and resolves it the same way (`type_`).
  done_: bool,
}

type model = {
  count: int,
  todos: array<todo>,
  draft: string,
  saving: bool,
}

type msg =
  | Increment
  | Decrement
  | SetDraft(string)
  | AddTodo
  | ToggleTodo(int)
  | Save
  | Saved

let init: model = {count: 0, todos: [], draft: "", saving: false}

let reduce = (model: model, msg: msg): model =>
  switch msg {
  | Increment => {...model, count: model.count + 1}
  | Decrement => {...model, count: model.count - 1}
  | SetDraft(text) => {...model, draft: text}
  | AddTodo =>
    if model.draft == "" {
      model
    } else {
      {
        ...model,
        todos: Array.concat(model.todos, [{text: model.draft, done_: false}]),
        draft: "",
      }
    }
  | ToggleTodo(index) => {
      ...model,
      todos: model.todos->Array.mapWithIndex((todo, i) =>
        i == index ? {...todo, done_: !todo.done_} : todo
      ),
    }
  | Save => {...model, saving: true}
  | Saved => {...model, saving: false}
  }

// --- codec: one msg <-> JSON.t, decode errors name the bad field ----------

let encode = (msg: msg): JSON.t =>
  switch msg {
  | Increment => JSON.Object(Dict.fromArray([("tag", JSON.Encode.string("Increment"))]))
  | Decrement => JSON.Object(Dict.fromArray([("tag", JSON.Encode.string("Decrement"))]))
  | SetDraft(text) =>
    JSON.Object(
      Dict.fromArray([
        ("tag", JSON.Encode.string("SetDraft")),
        ("text", JSON.Encode.string(text)),
      ]),
    )
  | AddTodo => JSON.Object(Dict.fromArray([("tag", JSON.Encode.string("AddTodo"))]))
  | ToggleTodo(index) =>
    JSON.Object(
      Dict.fromArray([
        ("tag", JSON.Encode.string("ToggleTodo")),
        ("index", JSON.Encode.int(index)),
      ]),
    )
  | Save => JSON.Object(Dict.fromArray([("tag", JSON.Encode.string("Save"))]))
  | Saved => JSON.Object(Dict.fromArray([("tag", JSON.Encode.string("Saved"))]))
  }

let decode = (json: JSON.t): result<msg, string> =>
  switch json {
  | JSON.Object(dict) =>
    switch Dict.get(dict, "tag") {
    | Some(JSON.String("Increment")) => Ok(Increment)
    | Some(JSON.String("Decrement")) => Ok(Decrement)
    | Some(JSON.String("SetDraft")) =>
      switch Dict.get(dict, "text") {
      | Some(JSON.String(text)) => Ok(SetDraft(text))
      | _ => Error("SetDraft: missing or non-string \"text\"")
      }
    | Some(JSON.String("AddTodo")) => Ok(AddTodo)
    | Some(JSON.String("ToggleTodo")) =>
      switch Dict.get(dict, "index") {
      | Some(JSON.Number(n)) => Ok(ToggleTodo(Float.toInt(n)))
      | _ => Error("ToggleTodo: missing or non-number \"index\"")
      }
    | Some(JSON.String("Save")) => Ok(Save)
    | Some(JSON.String("Saved")) => Ok(Saved)
    | Some(JSON.String(other)) => Error(`unknown tag "${other}"`)
    | _ => Error("missing or non-string \"tag\"")
    }
  | _ => Error("expected a JSON object")
  }

let codec: Rewind.codec<msg> = {encode, decode}

// --- view -------------------------------------------------------------

@react.component
let make = () => {
  let rewind = Rewind.use(~name="demo", ~codec, reduce, init)

  // Save effect: reads `rewind.live`, never `rewind.model` -- see the
  // module comment and DESIGN.md §3. A paused, stale view must not be
  // able to (re)trigger this timer.
  React.useEffect1(() => {
    if rewind.live.saving {
      let id = setTimeout(() => rewind.dispatch(Saved), 800)
      Some(() => clearTimeout(id))
    } else {
      None
    }
  }, [rewind.live.saving])

  // View: renders only `rewind.model` -- the paused entry when paused,
  // the live model otherwise.
  let model = rewind.model

  <div>
    <section>
      <button onClick={_ => rewind.dispatch(Decrement)}> {React.string("−")} </button>
      <span> {React.string(Int.toString(model.count))} </span>
      <button onClick={_ => rewind.dispatch(Increment)}> {React.string("+")} </button>
    </section>
    <section>
      <input
        placeholder="New todo"
        value={model.draft}
        onChange={evt => rewind.dispatch(SetDraft(JsxEvent.Form.target(evt)["value"]))}
      />
      <button onClick={_ => rewind.dispatch(AddTodo)}> {React.string("Add")} </button>
    </section>
    <ul>
      {model.todos
      ->Array.mapWithIndex((todo, i) =>
        <li key={Int.toString(i)}>
          <label>
            <input
              type_="checkbox"
              checked={todo.done_}
              onChange={_ => rewind.dispatch(ToggleTodo(i))}
            />
            {React.string(todo.text)}
          </label>
        </li>
      )
      ->React.array}
    </ul>
    <section>
      <button onClick={_ => rewind.dispatch(Save)}> {React.string("Save")} </button>
      <span> {React.string(model.saving ? "Saving…" : "Saved")} </span>
    </section>
  </div>
}
