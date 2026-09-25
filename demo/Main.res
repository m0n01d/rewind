// Mounts the demo app into #root. Side effect only -- no app logic here;
// Model/Msg/reduce/view all live in Demo.res.

switch ReactDOM.querySelector("#root") {
| Some(el) =>
  let root = ReactDOM.Client.createRoot(el)
  ReactDOM.Client.Root.render(root, <Demo />)
| None => Console.error("demo: #root not found")
}
