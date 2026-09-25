// Mounts the panel's own React root, isolated in a shadow DOM so its
// styles can't leak into (or be leaked by) the host page. `ensureMounted`
// only builds the shell here; the UI itself is wired in once
// RewindPanelState/the view components exist.

let mounted = ref(false)

let ensureMounted = (): unit =>
  if !mounted.contents {
    mounted.contents = true
    let host = RewindDom.createElement("div")
    RewindDom.appendChild(RewindDom.body, host)
    let shadow = RewindDom.attachShadow(host, {mode: "open"})
    let style = RewindDom.createElement("style")
    RewindDom.setTextContent(style, ":host { all: initial; }")
    RewindDom.shadowAppendChild(shadow, style)
    let mountPoint = RewindDom.createElement("div")
    RewindDom.shadowAppendChild(shadow, mountPoint)
    let root = ReactDOM.Client.createRoot(mountPoint)
    ReactDOM.Client.Root.render(root, React.null)
  }
