import EventKit
import Foundation

enum RemindersError: Error, CustomStringConvertible {
    case accessDenied
    case listNotFound(String)
    case reminderNotFound(String)
    case saveFailed(String)

    var description: String {
        switch self {
        case .accessDenied:
            return "Reminders access denied. Grant access in System Settings → Privacy & Security → Reminders."
        case .listNotFound(let s):
            return "Reminder list not found: \(s)"
        case .reminderNotFound(let s):
            return "Reminder not found: \(s)"
        case .saveFailed(let s):
            return "Failed to save reminder: \(s)"
        }
    }
}

enum ReminderStatus: String {
    case incomplete
    case completed
    case all
}

private struct ReminderRow: Sendable {
    let id: String
    let title: String
    let completed: Bool
    let list: String
    let notes: String?
    let due: Date?
    let completedAt: Date?
    let priority: Int

    init(_ r: EKReminder) {
        id = r.calendarItemIdentifier
        title = r.title ?? ""
        completed = r.isCompleted
        list = r.calendar?.title ?? ""
        notes = (r.notes?.isEmpty == false) ? r.notes : nil
        due = r.dueDateComponents?.date
        completedAt = r.completionDate
        priority = r.priority
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "completed": completed,
            "list": list,
            "priority": priority
        ]
        if let notes { dict["notes"] = notes }
        if let due { dict["due"] = JSONHelpers.iso(due) }
        if let completedAt { dict["completed_at"] = JSONHelpers.iso(completedAt) }
        return dict
    }
}

enum RemindersService {
    private static func requestAccess(_ store: EKEventStore) async throws {
        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToReminders()
            if !granted { throw RemindersError.accessDenied }
        } else {
            let granted = try await store.requestAccess(to: .reminder)
            if !granted { throw RemindersError.accessDenied }
        }
    }

    static func listLists() async throws -> [[String: Any]] {
        let store = EKEventStore()
        try await requestAccess(store)
        return store.calendars(for: .reminder).map { list in
            [
                "id": list.calendarIdentifier,
                "title": list.title,
                "source": list.source.title,
                "allowsContentModifications": list.allowsContentModifications
            ]
        }
    }

    static func listReminders(listName: String?,
                              status: ReminderStatus,
                              dueAfter: Date?,
                              dueBefore: Date?,
                              limit: Int) async throws -> [[String: Any]] {
        let store = EKEventStore()
        try await requestAccess(store)

        let calendars: [EKCalendar]?
        if let name = listName {
            let match = store.calendars(for: .reminder).first { $0.title == name || $0.calendarIdentifier == name }
            guard let c = match else { throw RemindersError.listNotFound(name) }
            calendars = [c]
        } else {
            calendars = nil
        }

        let predicate: NSPredicate
        switch status {
        case .incomplete:
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: dueAfter,
                ending: dueBefore,
                calendars: calendars
            )
        case .completed:
            predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: dueAfter,
                ending: dueBefore,
                calendars: calendars
            )
        case .all:
            predicate = store.predicateForReminders(in: calendars)
        }

        let rows: [ReminderRow] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                let mapped = (result ?? []).map(ReminderRow.init)
                cont.resume(returning: mapped)
            }
        }

        return rows.prefix(limit).map { $0.toDictionary() }
    }

    static func createReminder(title: String,
                               listName: String?,
                               dueDate: Date?,
                               notes: String?,
                               priority: Int?) async throws -> [String: Any] {
        let store = EKEventStore()
        try await requestAccess(store)

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        if let p = priority { reminder.priority = max(0, min(9, p)) }

        if let name = listName {
            guard let list = store.calendars(for: .reminder).first(where: { $0.title == name || $0.calendarIdentifier == name }) else {
                throw RemindersError.listNotFound(name)
            }
            reminder.calendar = list
        } else if let def = store.defaultCalendarForNewReminders() {
            reminder.calendar = def
        } else {
            throw RemindersError.listNotFound("(no default reminder list)")
        }

        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw RemindersError.saveFailed(error.localizedDescription)
        }

        var dict: [String: Any] = [
            "id": reminder.calendarItemIdentifier,
            "title": reminder.title ?? "",
            "list": reminder.calendar?.title ?? "",
            "priority": reminder.priority
        ]
        if let due = reminder.dueDateComponents?.date { dict["due"] = JSONHelpers.iso(due) }
        if let n = reminder.notes, !n.isEmpty { dict["notes"] = n }
        return dict
    }

    static func completeReminder(id: String) async throws -> [String: Any] {
        let store = EKEventStore()
        try await requestAccess(store)

        let predicate = store.predicateForReminders(in: nil)
        let row: ReminderRow = try await withCheckedThrowingContinuation { cont in
            store.fetchReminders(matching: predicate) { result in
                guard let target = result?.first(where: { $0.calendarItemIdentifier == id }) else {
                    cont.resume(throwing: RemindersError.reminderNotFound(id))
                    return
                }
                target.isCompleted = true
                target.completionDate = Date()
                do {
                    try store.save(target, commit: true)
                    cont.resume(returning: ReminderRow(target))
                } catch {
                    cont.resume(throwing: RemindersError.saveFailed(error.localizedDescription))
                }
            }
        }
        return row.toDictionary()
    }
}
