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
                name: "contacts_search",
                description: "Search contacts by name, email, or phone number. Returns up to `limit` matches.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Name, email, or phone number to search for.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of contacts to return. Default 20.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "contacts_create",
                description: "Create a new contact. At least one of given_name, family_name, or organization is required.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "given_name": .object([
                            "type": .string("string"),
                            "description": .string("First name.")
                        ]),
                        "family_name": .object([
                            "type": .string("string"),
                            "description": .string("Last name.")
                        ]),
                        "organization": .object([
                            "type": .string("string"),
                            "description": .string("Company or organization name.")
                        ]),
                        "phones": .object([
                            "type": .string("array"),
                            "description": .string("Phone numbers as strings."),
                            "items": .object(["type": .string("string")])
                        ]),
                        "emails": .object([
                            "type": .string("array"),
                            "description": .string("Email addresses as strings."),
                            "items": .object(["type": .string("string")])
                        ])
                    ])
                ])
            ),
            Tool(
                name: "photos_list_albums",
                description: "List user-created albums and non-empty smart albums in the Photos library.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            ),
            Tool(
                name: "photos_list_people",
                description: "List named people recognized by Photos, with identity IDs and counts of visible, non-deleted assets. Requires full Photos access and read access to the system Photos database (may require Full Disk Access).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Optional case- and diacritic-insensitive substring of a name or identity ID.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum identities to return. Default 100.")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),
            Tool(
                name: "photos_list_pets",
                description: "List named pets recognized by Photos, with identity IDs and counts of visible, non-deleted assets. Requires full Photos access and read access to the system Photos database (may require Full Disk Access).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Optional case- and diacritic-insensitive substring of a name or identity ID.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum identities to return. Default 100.")
                        ])
                    ]),
                    "additionalProperties": .bool(false)
                ])
            ),
            Tool(
                name: "photos_search",
                description: "Search photos and videos by date range, favorites, media type, album, recognized person, and/or recognized pet. All supplied filters must match. Returns metadata. People/pet filters require full Photos access and read access to the system Photos database (may require Full Disk Access).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "album_id": .object([
                            "type": .string("string"),
                            "description": .string("Optional album localIdentifier (from photos_list_albums) to restrict the query.")
                        ]),
                        "person": .object([
                            "type": .string("string"),
                            "description": .string("Exact full name, display name, or identity ID from photos_list_people. Case- and diacritic-insensitive. Duplicate names match any corresponding person; use an ID to disambiguate.")
                        ]),
                        "pet": .object([
                            "type": .string("string"),
                            "description": .string("Exact name, display name, or identity ID from photos_list_pets. Case- and diacritic-insensitive. Duplicate names match any corresponding pet; use an ID to disambiguate.")
                        ]),
                        "after": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 lower bound on creationDate.")
                        ]),
                        "before": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 upper bound on creationDate.")
                        ]),
                        "favorites_only": .object([
                            "type": .string("boolean"),
                            "description": .string("Only return assets marked as favorite.")
                        ]),
                        "media_type": .object([
                            "type": .string("string"),
                            "description": .string("One of: image, video, audio.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of assets. Default 50.")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "photos_export",
                description: "Export the full-resolution asset (original image or video) to a file path on disk.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Photo localIdentifier from photos_search.")
                        ]),
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Output file path. Existing files are overwritten. ~ is expanded.")
                        ])
                    ]),
                    "required": .array([.string("id"), .string("path")])
                ])
            ),
            Tool(
                name: "photos_view",
                description: "Return a downsized JPEG of an image asset as inline image content. Videos and audio are not supported.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("Photo localIdentifier from photos_search.")
                        ]),
                        "max_dimension": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum width/height in pixels. Default 512.")
                        ])
                    ]),
                    "required": .array([.string("id")])
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
                name: "reminders_list_lists",
                description: "List all reminder lists (Reminders app calendars of type .reminder).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "additionalProperties": .bool(false)
                ])
            ),
            Tool(
                name: "reminders_list",
                description: "List reminders. By default returns incomplete reminders across all lists.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "list": .object([
                            "type": .string("string"),
                            "description": .string("Optional reminder list title or identifier.")
                        ]),
                        "status": .object([
                            "type": .string("string"),
                            "description": .string("One of: incomplete (default), completed, all.")
                        ]),
                        "due_after": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 lower bound. For status=completed this is the completion date lower bound.")
                        ]),
                        "due_before": .object([
                            "type": .string("string"),
                            "description": .string("ISO 8601 upper bound. For status=completed this is the completion date upper bound.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum number of reminders to return. Default 50.")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "reminders_create",
                description: "Create a new reminder.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "title": .object([
                            "type": .string("string"),
                            "description": .string("Reminder title.")
                        ]),
                        "list": .object([
                            "type": .string("string"),
                            "description": .string("Optional reminder list title or identifier. Defaults to the system default list.")
                        ]),
                        "due": .object([
                            "type": .string("string"),
                            "description": .string("Optional ISO 8601 due date/time.")
                        ]),
                        "notes": .object([
                            "type": .string("string"),
                            "description": .string("Optional notes.")
                        ]),
                        "priority": .object([
                            "type": .string("integer"),
                            "description": .string("0=none, 1=high, 5=medium, 9=low. Default 0.")
                        ])
                    ]),
                    "required": .array([.string("title")])
                ])
            ),
            Tool(
                name: "reminders_complete",
                description: "Mark a reminder as completed by its identifier.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "id": .object([
                            "type": .string("string"),
                            "description": .string("calendarItemIdentifier from reminders_list or reminders_create.")
                        ])
                    ]),
                    "required": .array([.string("id")])
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
