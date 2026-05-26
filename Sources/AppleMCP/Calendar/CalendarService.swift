import EventKit
import Foundation

enum CalendarError: Error, CustomStringConvertible {
    case accessDenied
    case calendarNotFound(String)
    case invalidDates
    case saveFailed(String)

    var description: String {
        switch self {
        case .accessDenied:
            return "Calendar access denied. Grant access in System Settings → Privacy & Security → Calendar."
        case .calendarNotFound(let name):
            return "Calendar not found: \(name)"
        case .invalidDates:
            return "Invalid or missing start/end dates."
        case .saveFailed(let s):
            return "Failed to save event: \(s)"
        }
    }
}

enum CalendarService {
    private static func requestAccess(_ store: EKEventStore) async throws {
        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            if !granted { throw CalendarError.accessDenied }
        } else {
            let granted = try await store.requestAccess(to: .event)
            if !granted { throw CalendarError.accessDenied }
        }
    }

    static func listCalendars() async throws -> [[String: Any]] {
        let store = EKEventStore()
        try await requestAccess(store)
        return store.calendars(for: .event).map { cal in
            [
                "id": cal.calendarIdentifier,
                "title": cal.title,
                "source": cal.source.title,
                "allowsContentModifications": cal.allowsContentModifications,
                "type": typeName(cal.type)
            ]
        }
    }

    static func listEvents(start: Date, end: Date, calendarName: String?) async throws -> [[String: Any]] {
        let store = EKEventStore()
        try await requestAccess(store)
        let calendars: [EKCalendar]?
        if let name = calendarName {
            let match = store.calendars(for: .event).first { $0.title == name || $0.calendarIdentifier == name }
            guard let c = match else { throw CalendarError.calendarNotFound(name) }
            calendars = [c]
        } else {
            calendars = nil
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        return events.map { e in
            var dict: [String: Any] = [
                "id": e.eventIdentifier ?? "",
                "title": e.title ?? "",
                "start": JSONHelpers.iso(e.startDate),
                "end": JSONHelpers.iso(e.endDate),
                "allDay": e.isAllDay,
                "calendar": e.calendar.title
            ]
            if let loc = e.location, !loc.isEmpty { dict["location"] = loc }
            if let notes = e.notes, !notes.isEmpty { dict["notes"] = notes }
            if let url = e.url?.absoluteString { dict["url"] = url }
            if let attendees = e.attendees, !attendees.isEmpty {
                dict["attendees"] = attendees.compactMap { $0.url.absoluteString }
            }
            return dict
        }
    }

    static func createEvent(title: String,
                            start: Date,
                            end: Date,
                            calendarName: String?,
                            location: String?,
                            notes: String?,
                            allDay: Bool) async throws -> [String: Any] {
        guard end >= start else { throw CalendarError.invalidDates }
        let store = EKEventStore()
        try await requestAccess(store)
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.location = location
        event.notes = notes

        if let name = calendarName {
            guard let cal = store.calendars(for: .event).first(where: { $0.title == name || $0.calendarIdentifier == name }) else {
                throw CalendarError.calendarNotFound(name)
            }
            event.calendar = cal
        } else if let def = store.defaultCalendarForNewEvents {
            event.calendar = def
        } else {
            throw CalendarError.calendarNotFound("(no default calendar)")
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }

        return [
            "id": event.eventIdentifier ?? "",
            "title": event.title ?? "",
            "start": JSONHelpers.iso(event.startDate),
            "end": JSONHelpers.iso(event.endDate),
            "calendar": event.calendar.title
        ]
    }

    private static func typeName(_ t: EKCalendarType) -> String {
        switch t {
        case .local: return "local"
        case .calDAV: return "caldav"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "unknown"
        }
    }
}
