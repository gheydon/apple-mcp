import Foundation
import MCP

enum ToolDefinitions {
    static func all() -> [Tool] {
        [
            Tool(
                name: "calendar_list_calendars",
                description: "List all available calendars accessible to the user.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            ),
            Tool(
                name: "calendar_list_events",
                description: "List Calendar events in a date range. Dates are ISO 8601 strings (e.g. 2026-05-26T00:00:00Z).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "start": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 start date/time. Defaults to now.")
                        ]),
                        "end": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 end date/time. Defaults to start + 7 days.")
                        ]),
                        "calendar": .object([
                            "type": .string("string"),
                            "description": .string("Optional calendar title or identifier to restrict the query.")
                        ])
                    ]),
                    "required": .array([])
                ])
            ),
            Tool(
                name: "calendar_create_event",
                description: "Create a new event in Calendar.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object([
                            "type": .string("string"),
                            "description": .string("Event title.")
                        ]),
                        "start": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 start date/time.")
                        ]),
                        "end": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 end date/time.")
                        ]),
                        "calendar": .object([
                            "type": .string("string"),
                            "description": .string("Optional calendar title or identifier. Defaults to the system default.")
                        ]),
                        "location": .object([
                            "type": .string("string"),
                            "description": .string("Optional location.")
                        ]),
                        "notes": .object([
                            "type": .string("string"),
                            "description": .string("Optional notes/description.")
                        ]),
                        "all_day": .object([
                            "type": .string("boolean"),
                            "description": .string("Whether the event is all-day. Defaults to false.")
                        ])
                    ]),
                    "required": .array([.string("title"), .string("start"), .string("end")])
                ])
            ),
            Tool(
                name: "messages_list_chats",
                description: "List recent iMessage/SMS chats from ~/Library/Messages/chat.db. Requires Full Disk Access for the host process.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of chats to return. Default 20.")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "messages_recent",
                description: "List recent messages, optionally filtered to a chat. Body text is recovered from `attributedBody` when the `text` column is empty.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "chat_identifier": .object([
                            "type": .string("string"),
                            "description": .string("Optional chat identifier (e.g. phone number, Apple ID, or group GUID).")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of messages to return. Default 30.")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "messages_search",
                description: "Search messages by substring. Note: only searches the `text` column; attributedBody-only messages are not matched.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Substring to search for.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of results to return. Default 30.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "messages_send",
                description: "Send a message via the Messages app. Requires Automation permission to control Messages.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "recipient": .object([
                            "type": .string("string"),
                            "description": .string("Phone number (with country code) or Apple ID email.")
                        ]),
                        "body": .object([
                            "type": .string("string"),
                            "description": .string("Message text to send.")
                        ]),
                        "service": .object([
                            "type": .string("string"),
                            "description": .string("Service to use: \"iMessage\" (default) or \"SMS\".")
                        ])
                    ]),
                    "required": .array([.string("recipient"), .string("body")])
                ])
            )
        ]
    }
}
