// Proves the build + test harness works at the scaffold commit, before
// RewindHistory, RewindCore and RewindCodec exist.
let kit = TestKit.make()
TestKit.check(kit, "packageVersion is 0.1.0", RewindVersion.packageVersion == "0.1.0")
TestKit.finish(kit, "ScaffoldTest")
