import Foundation
import MCP

enum ToolHandlers {
    static func handle(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            switch name {
            case "calendar_list_calendars":
                let cals = try await CalendarService.listCalendars()
                return JSONHelpers.jsonResult(cals)

            case "calendar_list_events":
                let now = Date()
                let start = JSONHelpers.date(arguments, "start") ?? now
                let end = JSONHelpers.date(arguments, "end") ?? start.addingTimeInterval(60 * 60 * 24 * 7)
                let cal = JSONHelpers.string(arguments, "calendar")
                let events = try await CalendarService.listEvents(start: start, end: end, calendarName: cal)
                return JSONHelpers.jsonResult(events)

            case "calendar_create_event":
                guard let title = JSONHelpers.string(arguments, "title"),
                      let start = JSONHelpers.date(arguments, "start"),
                      let end = JSONHelpers.date(arguments, "end") else {
                    return JSONHelpers.errorResult("title, start, and end are required (start/end as ISO 8601 strings)")
                }
                let created = try await CalendarService.createEvent(
                    title: title,
                    start: start,
                    end: end,
                    calendarName: JSONHelpers.string(arguments, "calendar"),
                    location: JSONHelpers.string(arguments, "location"),
                    notes: JSONHelpers.string(arguments, "notes"),
                    allDay: JSONHelpers.bool(arguments, "all_day") ?? false
                )
                return JSONHelpers.jsonResult(created)

            case "messages_list_chats":
                let limit = JSONHelpers.int(arguments, "limit") ?? 20
                let chats = try MessagesDB.listChats(limit: limit)
                return JSONHelpers.jsonResult(chats)

            case "messages_recent":
                let limit = JSONHelpers.int(arguments, "limit") ?? 30
                let chatId = JSONHelpers.string(arguments, "chat_identifier")
                let messages = try MessagesDB.recentMessages(chatIdentifier: chatId, limit: limit)
                return JSONHelpers.jsonResult(messages)

            case "messages_search":
                guard let query = JSONHelpers.string(arguments, "query"), !query.isEmpty else {
                    return JSONHelpers.errorResult("query is required")
                }
                let limit = JSONHelpers.int(arguments, "limit") ?? 30
                let results = try MessagesDB.searchMessages(query: query, limit: limit)
                return JSONHelpers.jsonResult(results)

            case "messages_send":
                guard let recipient = JSONHelpers.string(arguments, "recipient"), !recipient.isEmpty,
                      let body = JSONHelpers.string(arguments, "body"), !body.isEmpty else {
                    return JSONHelpers.errorResult("recipient and body are required")
                }
                let service = JSONHelpers.string(arguments, "service") ?? "iMessage"
                try MessagesSender.send(to: recipient, body: body, service: service)
                return JSONHelpers.jsonResult([
                    "sent": true,
                    "recipient": recipient,
                    "service": service
                ])

            default:
                return JSONHelpers.errorResult("unknown tool: \(name)")
            }
        } catch let e as CustomStringConvertible {
            return JSONHelpers.errorResult(e.description)
        } catch {
            return JSONHelpers.errorResult(error.localizedDescription)
        }
    }
}
