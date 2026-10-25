import Foundation
import SQLite3

enum PhotosIdentityError: Error, CustomStringConvertible {
    case libraryUnavailable(String)
    case unsupportedSchema(String)
    case queryFailed(String)

    var description: String {
        switch self {
        case .libraryUnavailable(let detail):
            return "Cannot read the system Photos library (\(detail)). Open Photos and designate a System Photo Library in Settings → General. Grant Full Disk Access to the host application if access is denied."
        case .unsupportedSchema(let detail):
            return "People/pet search does not support this Photos database schema: \(detail). Other Photos tools remain available."
        case .queryFailed(let detail): return "Photos identity query failed: \(detail)"
        }
    }
}

enum PhotoIdentityKind: String, Sendable {
    case person
    case pet
}

struct PhotoIdentity: Sendable {
    let id: String
    let name: String
    let displayName: String
    let kind: PhotoIdentityKind
    let photoCount: Int

    func matches(_ value: String) -> Bool {
        [id, name, displayName].contains {
            $0.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func toDictionary() -> [String: Any] {
        ["id": id, "name": name, "display_name": displayName,
         "kind": kind.rawValue, "photo_count": photoCount]
    }
}

// Undocumented ZPERSON.ZDETECTIONTYPE values observed in Photos libraries.
private let humanDetectionType = 1
private let petDetectionTypes = [3, 4]
private let busyTimeoutMilliseconds: Int32 = 2000

final class PhotosIdentityDB {
    private let db: OpaquePointer
    private let includesTemporalFaces: Bool

    static func systemDatabaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let preferences = [
            "Library/Group Containers/group.com.apple.photolibraryd.private/Library/Preferences/group.com.apple.photolibraryd.private.plist",
            "Library/Containers/com.apple.photolibraryd/Data/Library/Preferences/com.apple.photolibraryd.plist"
        ]
        var failures: [String] = []
        for path in preferences {
            let url = home.appendingPathComponent(path)
            do {
                let data = try Data(contentsOf: url)
                let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
                if let values = plist as? [String: Any],
                   let path = values["SystemLibraryPath"] as? String, !path.isEmpty {
                    return URL(fileURLWithPath: path).appendingPathComponent("database/Photos.sqlite")
                }
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        throw PhotosIdentityError.libraryUnavailable(
            "SystemLibraryPath not found in Photos preferences. \(failures.joined(separator: "; "))"
        )
    }

    init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let detail = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite error \(result)"
            if let handle { sqlite3_close(handle) }
            throw PhotosIdentityError.libraryUnavailable(detail)
        }
        sqlite3_busy_timeout(handle, busyTimeoutMilliseconds)
        do {
            try Self.requireColumns(["Z_PK", "ZPERSONUUID", "ZFULLNAME", "ZDISPLAYNAME", "ZDETECTIONTYPE", "ZMERGETARGETPERSON"], table: "ZPERSON", db: handle)
            try Self.requireColumns(["Z_PK", "ZUUID", "ZHIDDEN", "ZTRASHEDSTATE"], table: "ZASSET", db: handle)
            try Self.requireColumns(["ZASSETFORFACE", "ZPERSONFORFACE"], table: "ZDETECTEDFACE", db: handle)
            includesTemporalFaces = try Self.columns(in: "ZDETECTEDFACE", db: handle).isSuperset(of: [
                "ZASSETFORTEMPORALDETECTEDFACES", "ZPERSONFORTEMPORALDETECTEDFACES"
            ])
        } catch {
            sqlite3_close(handle)
            throw error
        }
        db = handle
    }

    deinit { sqlite3_close(db) }

    func list(kind: PhotoIdentityKind, query: String?, limit: Int) throws -> [PhotoIdentity] {
        let statement = try Self.prepare("""
            \(namedIdentityFaces(kind: kind, select: "COUNT(DISTINCT a.ZUUID)"))
            GROUP BY p.Z_PK
            ORDER BY COALESCE(NULLIF(p.ZFULLNAME, ''), p.ZDISPLAYNAME) COLLATE NOCASE, p.ZPERSONUUID
            """, db: db)
        defer { sqlite3_finalize(statement) }
        var identities: [PhotoIdentity] = []
        while try Self.step(statement, db: db) {
            let identity = Self.identity(from: statement, kind: kind, photoCount: Int(sqlite3_column_int64(statement, 3)))
            if let query, !query.isEmpty,
               ![identity.id, identity.name, identity.displayName].contains(where: {
                   $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
               }) { continue }
            identities.append(identity)
            if identities.count == limit { break }
        }
        return identities
    }

    func assetUUIDs(person: String?, pet: String?) throws -> Set<String> {
        var matching: Set<String>?
        for (kind, filter) in [(PhotoIdentityKind.person, person), (.pet, pet)] {
            guard let filter else { continue }
            let value = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            // Duplicate names deliberately match every corresponding identity.
            let statement = try Self.prepare(namedIdentityFaces(kind: kind, select: "a.ZUUID"), db: db)
            defer { sqlite3_finalize(statement) }
            var uuids = Set<String>()
            while try Self.step(statement, db: db) {
                if Self.identity(from: statement, kind: kind, photoCount: 0).matches(value) {
                    uuids.insert(Self.text(statement, 3).uppercased())
                }
            }
            matching = matching.map { $0.intersection(uuids) } ?? uuids
        }
        return matching ?? []
    }

    // Columns 0–2 are identity UUID, full name, and display name; column 3 is `select`. Faces on
    // merged identities count toward the merge target.
    private func namedIdentityFaces(kind: PhotoIdentityKind, select: String) -> String {
        var faces = "SELECT ZPERSONFORFACE AS person, ZASSETFORFACE AS asset FROM ZDETECTEDFACE"
        if includesTemporalFaces {
            faces += " UNION SELECT ZPERSONFORTEMPORALDETECTEDFACES, ZASSETFORTEMPORALDETECTEDFACES FROM ZDETECTEDFACE"
        }
        let detectionTypes = kind == .person ? [humanDetectionType] : petDetectionTypes
        return """
            WITH RECURSIVE identity_map(source, target) AS (
                SELECT Z_PK, Z_PK FROM ZPERSON
                UNION
                SELECT m.source, p.ZMERGETARGETPERSON
                FROM identity_map m JOIN ZPERSON p ON p.Z_PK = m.target
                WHERE COALESCE(p.ZMERGETARGETPERSON, 0) != 0
            ), faces AS (\(faces))
            SELECT p.ZPERSONUUID, p.ZFULLNAME, p.ZDISPLAYNAME, \(select)
            FROM ZPERSON p
            JOIN identity_map m ON m.target = p.Z_PK
            JOIN faces f ON f.person = m.source
            JOIN ZASSET a ON a.Z_PK = f.asset
            WHERE p.ZDETECTIONTYPE IN (\(detectionTypes.map(String.init).joined(separator: ", ")))
              AND COALESCE(p.ZMERGETARGETPERSON, 0) = 0
              AND COALESCE(a.ZHIDDEN, 0) = 0 AND COALESCE(a.ZTRASHEDSTATE, 0) = 0
              AND COALESCE(p.ZPERSONUUID, '') != ''
              AND (TRIM(COALESCE(p.ZFULLNAME, '')) != '' OR TRIM(COALESCE(p.ZDISPLAYNAME, '')) != '')
            """
    }

    private static func identity(from statement: OpaquePointer, kind: PhotoIdentityKind, photoCount: Int) -> PhotoIdentity {
        let fullName = text(statement, 1)
        let displayName = text(statement, 2)
        return PhotoIdentity(
            id: text(statement, 0),
            name: fullName.isEmpty ? displayName : fullName,
            displayName: displayName.isEmpty ? fullName : displayName,
            kind: kind,
            photoCount: photoCount
        )
    }

    private static func columns(in table: String, db: OpaquePointer) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))", db: db)
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while try step(statement, db: db) { names.insert(text(statement, 1)) }
        return names
    }

    private static func requireColumns(_ required: Set<String>, table: String, db: OpaquePointer) throws {
        let missing = try required.subtracting(columns(in: table, db: db))
        guard missing.isEmpty else {
            throw PhotosIdentityError.unsupportedSchema("\(table) is missing \(missing.sorted().joined(separator: ", "))")
        }
    }

    private static func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw PhotosIdentityError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        return statement
    }

    private static func step(_ statement: OpaquePointer, db: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw PhotosIdentityError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
}
