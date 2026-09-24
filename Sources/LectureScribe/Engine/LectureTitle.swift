import EventKit
import Foundation

struct CalendarSlot: Equatable {
    let title: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
}

@MainActor
enum LectureTitle {
    private static let store = EKEventStore()
    private static var accessResult: Bool?
    static let lookahead = 60.0

    static func currentEventTitle() async -> String? {
        guard await hasAccess() else { return nil }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(lookahead), calendars: nil)
        let slots = store.events(matching: predicate).map {
            CalendarSlot(title: $0.title, start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
        let title = pickTitle(from: slots, now: now)
        if let title { Log.engine("calendar event now: \(title)") }
        return title
    }

    static func pickTitle(from slots: [CalendarSlot], now: Date) -> String? {
        let timed = slots.filter { !$0.isAllDay && !($0.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        let running = timed.filter { $0.start <= now && $0.end > now }
        let candidates = running.isEmpty ? timed : running
        return candidates.max { $0.start < $1.start }?.title
    }

    private static func hasAccess() async -> Bool {
        if let accessResult { return accessResult }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        accessResult = granted
        Log.engine("calendar access: \(granted ? "granted" : "denied")")
        return granted
    }
}
