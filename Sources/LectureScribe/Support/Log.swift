import Foundation
import OSLog

enum Log {
    static let subsystem = "com.tcivie.lecturescribe"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    static func engine(_ message: String) {
        logger.info("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("[lecturescribe] \(message)\n".utf8))
    }
}
