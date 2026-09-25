// A module-level list of every mounted rewind session, so one shared panel
// UI can show all of them. Mirrors RewindStore's own subscribe/getSnapshot
// shape, so the panel can useSyncExternalStore on the registry the same
// way it does on one session.

let sessions: ref<array<RewindStore.session>> = ref([])
let listeners: ref<array<unit => unit>> = ref([])

let notify = (): unit => listeners.contents->Array.forEach(l => l())

// The first free "name", "name #2", "name #3", … among currently-registered
// sessions.
let uniqueName = (name: string): string =>
  if !(sessions.contents->Array.some(s => s.name == name)) {
    name
  } else {
    let n = ref(2)
    let candidate = ref(`${name} #${Int.toString(n.contents)}`)
    while sessions.contents->Array.some(s => s.name == candidate.contents) {
      n := n.contents + 1
      candidate := `${name} #${Int.toString(n.contents)}`
    }
    candidate.contents
  }

let add = (session: RewindStore.session): unit => {
  session.name = uniqueName(session.name)
  sessions.contents = Array.concat(sessions.contents, [session])
  notify()
}

let remove = (session: RewindStore.session): unit => {
  sessions.contents = sessions.contents->Array.filter(s => s.id != session.id)
  notify()
}

let subscribe = (onChange: unit => unit): (unit => unit) => {
  listeners.contents = Array.concat(listeners.contents, [onChange])
  () => listeners.contents = listeners.contents->Array.filter(l => l !== onChange)
}

// Cheap and correct without a cache: `sessions.contents` is only ever
// replaced (never mutated in place) by add/remove, so two calls with no
// add/remove between them return the same array reference already.
let getSnapshot = (): array<RewindStore.session> => sessions.contents

let anyPaused = (): bool =>
  sessions.contents->Array.some(s =>
    switch s.getSnapshot().cursor {
    | Some(_) => true
    | None => false
    }
  )
