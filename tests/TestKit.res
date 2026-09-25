// A small typed test helper shared by this package's test files. Each test
// file makes a TestKit.t, calls check for each case, then calls finish. A
// typed binding to process.exit gives a non-zero exit code on any failure,
// per the house rule against untyped escape hatches.

@val @scope("process")
external exitProcess: int => unit = "exit"

type t = {mutable passed: int, mutable failed: int}

let make = (): t => {passed: 0, failed: 0}

let check = (kit: t, name: string, cond: bool): unit =>
  if cond {
    kit.passed = kit.passed + 1
  } else {
    kit.failed = kit.failed + 1
    Console.log(`  FAIL: ${name}`)
  }

let finish = (kit: t, label: string): unit => {
  Console.log(`${label}: ${Int.toString(kit.passed)} passed, ${Int.toString(kit.failed)} failed`)
  if kit.failed > 0 {
    exitProcess(1)
  }
}
