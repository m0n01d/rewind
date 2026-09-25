// The only JS bindings in rewind's value printer. Each one is either total
// (defined by spec for every input, and it cannot throw) or is documented
// as safe to call only after a shape/tag check has already confirmed it
// applies -- RewindValue does that check first every time. Together with
// the stdlib Type.Classify.classify, these let RewindValue inspect an
// arbitrary 'a without Obj.magic, %raw, %%raw or %identity.

// An opaque handle to a JS value of unknown shape: a field read out of an
// object, or a Map/Set/array element. It is never inspected directly --
// it is always re-classified with classifyUnknown first, the same way the
// root value passed to RewindValue.make is.
type unknown

// Object.keys is defined for every object -- including arrays, class
// instances and null-prototype objects -- and always returns a real string
// array. It can't throw and can't return anything but string[].
@val
external keys: Type.Classify.object => array<string> = "Object.keys"

// A computed property read (`obj[key]`) can hold any JS value, so the
// result is typed `unknown` rather than assumed to be any particular
// shape -- the caller must classify it before using it. Reading a plain
// data property can't throw; only a throwing getter can, and RewindValue
// wraps every call to this binding in try/catch so a poisoned getter can't
// escape the module.
@get_index
external getField: (Type.Classify.object, string) => unknown = ""

// Array.isArray is a total predicate: the spec defines a boolean result
// for every input value, and it never throws.
@val
external isArray: Type.Classify.object => bool = "Array.isArray"

// Object.prototype.toString.call(x) is defined for every value and returns
// a "[object Tag]" string -- it's how a Map, a Set, a Date, a Blob, a File
// and a plain object are told apart without a type test that would need
// %raw. It can only throw if a value defines a Symbol.toStringTag getter
// that itself throws, which RewindValue wraps.
@val
external toStringTag: Type.Classify.object => string = "Object.prototype.toString.call"

// Array.from reads any iterable into a real array. Arrays, Maps and Sets
// are all iterable -- a Map yields [key, value] pairs, a Set and an array
// yield bare elements -- so each element is re-typed `unknown` rather than
// assumed to share one shape. Only call after the tag/isArray check
// confirms one of those three: Array.from throws TypeError on a
// non-iterable.
@val
external arrayFrom: Type.Classify.object => array<unknown> = "Array.from"

// String(x) called as a function (not `new String(x)`) is total for every
// value this module passes it, including a Date: valid or invalid, it
// always yields a string ("Invalid Date" for an invalid one) without
// throwing. Used as the safe pre-check for the Date branch, ahead of
// reading its ISO text.
@val
external stringOf: Type.Classify.object => string = "String"

// .toJSON() on a Date mirrors .toISOString() for a valid date, but returns
// JS null instead of throwing RangeError when the date is invalid -- so
// it's safe to call once the tag check confirms this is a Date, with no
// try/catch needed. Typed `unknown` because the result is either a string
// or null, and the caller classifies it to tell those apart.
@send
external dateToJSON: Type.Classify.object => unknown = "toJSON"

// .size is a plain data-property getter on a real Blob or File; call only
// after the tag check confirms one of those two tags.
@get
external blobSize: Type.Classify.object => float = "size"

// .type is a plain data-property getter on a real Blob or File (its MIME
// string, "" when unknown); call only after the tag check.
@get
external blobType: Type.Classify.object => string = "type"

// .name exists only on File, not Blob; call only after the tag check
// confirms [object File] specifically.
@get
external fileName: Type.Classify.object => string = "name"

// Re-classifies a value read out of a container (a field, an
// array/Map/Set element) with the same total stdlib classifier used for
// the root value, so RewindValue can recurse without ever casting.
let classifyUnknown = (u: unknown): Type.Classify.t => Type.Classify.classify(u)
