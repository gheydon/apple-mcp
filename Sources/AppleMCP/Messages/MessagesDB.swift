import Foundation
import SQLite3

enum MessagesError: Error, CustomStringConvertible {
    case databaseUnreachable(String)
    case queryFailed(String)

    var description: String {
        switch self {
        case .databaseUnreachable(let s):
            return "Cannot open Messages database (\(s)). Grant Full Disk Access to the host application in System Settings → Privacy & Security → Full Disk Access."
        case .queryFailed(let s):
            return "Query failed: \(s)"
        }
    }
}

// SQLITE_TRANSIENT marker — Swift can't import the C macro, so we redeclare it.
private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1)!, to: sqlite3_destructor_type.self)

// Mac epoch (2001-01-01) offset from Unix epoch.
private let macEpochOffset: TimeInterval = 978_307_200

enum MessagesDB {
    static var databasePath: String {
        (NSString(string: "~/Library/Messages/chat.db") as NSString).expandingTildeInPath
    }

    private static func open() throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(databasePath, &db, flags, nil)
        guard rc == SQLITE_OK, let handle = db else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "rc=\(rc)"
            if let d = db { sqlite3_close(d) }
            throw MessagesError.databaseUnreachable(msg)
        }
        return handle
    }

    private static func close(_ db: OpaquePointer) { sqlite3_close(db) }

    static func listChats(limit: Int) throws -> [[String: Any]] {
        let db = try open()
        defer { close(db) }
        let sql = """
            SELECT c.ROWID, c.chat_identifier, c.display_name, c.service_name,
                   MAX(m.date) AS last_date,
                   COUNT(cmj.message_id) AS message_count
            FROM chat c
            LEFT JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
            LEFT JOIN message m ON cmj.message_id = m.ROWID
            GROUP BY c.ROWID
            HAVING last_date IS NOT NULL
            ORDER BY last_date DESC
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MessagesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))

        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [
                "rowid": Int(sqlite3_column_int64(stmt, 0)),
                "chat_identifier": columnText(stmt, 1) ?? "",
                "display_name": columnText(stmt, 2) ?? "",
                "service": columnText(stmt, 3) ?? "",
                "message_count": Int(sqlite3_column_int64(stmt, 5))
            ]
            let rawDate = sqlite3_column_int64(stmt, 4)
            row["last_message"] = JSONHelpers.iso(dateFromMessageDate(rawDate))
            rows.append(row)
        }
        return rows
    }

    static func recentMessages(chatIdentifier: String?, limit: Int) throws -> [[String: Any]] {
        let db = try open()
        defer { close(db) }
        var sql = """
            SELECT m.ROWID, m.text, m.attributedBody, m.date, m.is_from_me,
                   h.id AS handle, c.chat_identifier
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            """
        if chatIdentifier != nil {
            sql += " WHERE c.chat_identifier = ?"
        }
        sql += " ORDER BY m.date DESC LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MessagesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        if let id = chatIdentifier {
            sqlite3_bind_text(stmt, bindIndex, id, -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        sqlite3_bind_int(stmt, bindIndex, Int32(limit))

        return collectMessages(stmt: stmt)
    }

    static func searchMessages(query: String, limit: Int) throws -> [[String: Any]] {
        let db = try open()
        defer { close(db) }
        let sql = """
            SELECT m.ROWID, m.text, m.attributedBody, m.date, m.is_from_me,
                   h.id AS handle, c.chat_identifier
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.text LIKE ?
            ORDER BY m.date DESC
            LIMIT ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MessagesError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        return collectMessages(stmt: stmt)
    }

    private static func collectMessages(stmt: OpaquePointer?) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = Int(sqlite3_column_int64(stmt, 0))
            let textCol = columnText(stmt, 1)
            let attributedBody = columnBlob(stmt, 2)
            let dateRaw = sqlite3_column_int64(stmt, 3)
            let fromMe = sqlite3_column_int(stmt, 4) != 0
            let handle = columnText(stmt, 5)
            let chatId = columnText(stmt, 6)

            let text: String
            if let t = textCol, !t.isEmpty {
                text = t
            } else if let blob = attributedBody, let extracted = AttributedBody.extractText(from: blob) {
                text = extracted
            } else {
                text = ""
            }

            rows.append([
                "rowid": rowid,
                "date": JSONHelpers.iso(dateFromMessageDate(dateRaw)),
                "from_me": fromMe,
                "handle": handle ?? "",
                "chat_identifier": chatId ?? "",
                "text": text
            ])
        }
        return rows
    }

    private static func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private static func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        let length = sqlite3_column_bytes(stmt, index)
        guard length > 0, let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: bytes, count: Int(length))
    }

    private static func dateFromMessageDate(_ raw: Int64) -> Date {
        // Modern macOS stores nanoseconds since Mac epoch; older databases stored seconds.
        let seconds: TimeInterval
        if raw > 1_000_000_000_000 {
            seconds = TimeInterval(raw) / 1_000_000_000.0
        } else {
            seconds = TimeInterval(raw)
        }
        return Date(timeIntervalSince1970: seconds + macEpochOffset)
    }
}
