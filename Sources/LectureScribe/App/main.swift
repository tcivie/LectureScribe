import Foundation

setvbuf(stdout, nil, _IONBF, 0)
let args = Args.parse(Array(CommandLine.arguments.dropFirst()))
do {
    try await runCommand(args)
} catch {
    print("❌ \(error.localizedDescription)")
    exit(1)
}
