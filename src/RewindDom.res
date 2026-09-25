// Minimal, hand-written DOM bindings for the panel. No DOM-binding package
// passed the gate: `@rescript/webapi`'s latest dist-tag was published
// 2024-11 and the only newer build is an alpha (checked 2026-09-25, see the
// commit message). Every external here is either spec-total for the inputs
// this module passes it, or is documented as safe only because of how this
// module uses it -- the same discipline as RewindJs.res.
//
// `Dom.element`, `Dom.window`, `Dom.event`, `Dom.eventTarget` and
// `Dom.htmlInputElement` are pervasive abstract types the ReScript compiler
// itself ships (confirmed by compiling a probe file with no package
// installed) -- not part of any binding library. `document.createElement`
// is spec-typed to return the base `Element`; this module only ever calls
// it with a fixed, known HTML tag name ("div", "style", "a", "input"), so
// every element it touches is, in fact, a real HTMLElement with `.click()`
// and attribute methods -- it just doesn't carry a more specific ReScript
// type for that, matching how `@rescript/react`'s own `ReactDOM.querySelector`
// and `Client.createRoot` are typed on plain `Dom.element` throughout.

@val external document: Dom.document = "document"
@val external window: Dom.window = "window"

@val @scope("document")
external createElement: string => Dom.element = "createElement"

@val @scope(("document", "body"))
external body: Dom.element = "body"

@send
external appendChild: (Dom.element, Dom.element) => unit = "appendChild"

@send
external setAttribute: (Dom.element, string, string) => unit = "setAttribute"

// The one property (not attribute) setter this module needs: the text
// inside the injected `<style>` element. `setAttribute("textContent", …)`
// would not work -- `textContent` is a property, not an HTML attribute.
@set
external setTextContent: (Dom.element, string) => unit = "textContent"

@send
external click: Dom.element => unit = "click"

// `scrollIntoView()`, no options: the zero-arg form is part of the spec
// (default alignment), and it is all the message list's auto-scroll needs.
@send
external scrollIntoView: Dom.element => unit = "scrollIntoView"

// --- shadow DOM ----------------------------------------------------------

type shadowRoot

type shadowOptions = {mode: string}

@send
external attachShadow: (Dom.element, shadowOptions) => shadowRoot = "attachShadow"

@send
external shadowAppendChild: (shadowRoot, Dom.element) => unit = "appendChild"

// --- window event listeners ------------------------------------------------
// Only the capture-phase, options-record form: the one shape the panel's
// paused-blocker actually registers on `window`. Buttons, the message list
// and the file input all live inside the panel's own React tree and use
// ordinary React event props (onClick, onChange, onKeyDown) instead --
// this module's listener binding exists only for the global BlockAll
// capture that must run outside any one React root.

type listenerOptions = {capture: bool}

@send
external addEventListener: (Dom.window, string, Dom.event => unit, listenerOptions) => unit =
  "addEventListener"

@send
external removeEventListener: (Dom.window, string, Dom.event => unit, listenerOptions) => unit =
  "removeEventListener"

@send external stopPropagation: Dom.event => unit = "stopPropagation"
@send external preventDefault: Dom.event => unit = "preventDefault"

@send
external composedPath: Dom.event => array<Dom.eventTarget> = "composedPath"

// `Array.prototype.includes` really is this generic: a `===` (SameValueZero)
// scan that does not care what its elements represent. The two independent
// type variables say exactly that and nothing more -- this claims no DOM
// capability for either side, so it stays honest while letting one call
// site compare a `composedPath()` array (`eventTarget_like<_baseClass>`)
// against a plain `Dom.element` host
// (`eventTarget_like<_node<_element<_baseClass>>>`), two different
// instantiations of the same compiler-pervasive phantom family. Verified by
// probe: this signature compiles and unifies for exactly that call; it does
// not unify `Dom.window` on the right, which this module never needs to.
@send
external includesEventTarget: (
  array<Dom.eventTarget_like<'a>>,
  Dom.eventTarget_like<'b>,
) => bool = "includes"

// --- export download -------------------------------------------------------

type blob

type blobOptions = {@as("type") type_: string}

@new external makeBlob: (array<string>, blobOptions) => blob = "Blob"

@val @scope("URL") external createObjectURL: blob => string = "createObjectURL"
@val @scope("URL") external revokeObjectURL: string => unit = "revokeObjectURL"

// --- file input (import) ----------------------------------------------------

type file
type fileList

// `.files` on an `<input type="file">` this module creates itself is never
// null -- that only happens for an input of a different `type`.
@get external files: Dom.element => fileList = "files"

@send @return(nullable)
external item: (fileList, int) => option<file> = "item"

@send external text: file => promise<string> = "text"
