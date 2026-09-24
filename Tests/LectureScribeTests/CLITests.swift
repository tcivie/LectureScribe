import Testing
@testable import LectureScribe

@Suite struct ArgsTests {
    @Test func parsesSubcommandAndOptions() {
        let args = Args.parse(["record", "--source", "system", "--title", "Week 1", "--duration", "30", "--no-polish"])
        #expect(args.sub == "record" && args.source == "system" && args.title == "Week 1")
        #expect(args.durationSeconds == 30 && args.noPolish)
    }

    @Test func appIsTheDefaultCommand() {
        #expect(Args.parse(["app"]).sub == "")
        #expect(Args.parse([]).sub == "")
    }

    @Test func collectsUnknownOptions() {
        #expect(Args.parse(["view", "--flaot"]).unknown == ["--flaot"])
    }

    @Test func missingValueIsNil() {
        #expect(Args.parse(["record", "--title"]).title == nil)
    }

    @Test(arguments: ["abc", "-5", "0"])
    func invalidDurationIsIgnored(raw: String) {
        #expect(Args.parse(["record", "--duration", raw]).durationSeconds == nil)
    }

    @Test func helpFlag() {
        #expect(Args.parse(["-h"]).help)
    }
}

@Suite struct SourceKindParsing {
    @Test func aliases() {
        #expect(parseSourceKind("Safari") == .system)
        #expect(parseSourceKind("MIC") == .microphone)
        #expect(parseSourceKind("2") == .microphone)
        #expect(parseSourceKind("nope") == nil)
    }

    // The old parser lowercased the whole argument, device name included.
    @Test func deviceNameKeepsItsCase() {
        #expect(parseSourceKind("device:MacBook Pro Microphone") == .device(name: "MacBook Pro Microphone"))
        #expect(parseSourceKind("device:") == nil)
    }

    @Test(arguments: [SourceKind.system, .microphone, .device(name: "USB Mic")])
    func storageKeyRoundTrips(kind: SourceKind) {
        #expect(SourceKind.from(storageKey: kind.storageKey) == kind)
    }
}
