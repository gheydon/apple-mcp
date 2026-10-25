import AppKit
import Foundation
import Photos

enum PhotosError: Error, CustomStringConvertible {
    case accessDenied
    case fullAccessRequired
    case assetNotFound(String)
    case albumNotFound(String)
    case exportFailed(String)
    case unsupportedMediaType(String)

    var description: String {
        switch self {
        case .accessDenied:
            return "Photos access denied. Grant access in System Settings → Privacy & Security → Photos."
        case .fullAccessRequired:
            return "People/pet search requires full Photos access; limited access cannot expose library-wide identities. Grant full access in System Settings → Privacy & Security → Photos."
        case .assetNotFound(let s): return "Photo not found: \(s)"
        case .albumNotFound(let s): return "Album not found: \(s)"
        case .exportFailed(let s): return "Export failed: \(s)"
        case .unsupportedMediaType(let s): return "Cannot view media type: \(s)"
        }
    }
}

private struct PhotoRow: Sendable {
    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let mediaType: String
    let mediaSubtypes: [String]
    let isFavorite: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let durationSeconds: Double?
    let latitude: Double?
    let longitude: Double?

    init(_ asset: PHAsset) {
        id = asset.localIdentifier
        creationDate = asset.creationDate
        modificationDate = asset.modificationDate
        mediaType = PhotosService.mediaTypeName(asset.mediaType)
        mediaSubtypes = PhotosService.subtypeNames(asset.mediaSubtypes)
        isFavorite = asset.isFavorite
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        durationSeconds = asset.mediaType == .video ? asset.duration : nil
        if let loc = asset.location {
            latitude = loc.coordinate.latitude
            longitude = loc.coordinate.longitude
        } else {
            latitude = nil
            longitude = nil
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "media_type": mediaType,
            "favorite": isFavorite,
            "width": pixelWidth,
            "height": pixelHeight
        ]
        if let d = creationDate { dict["created"] = JSONHelpers.iso(d) }
        if let m = modificationDate { dict["modified"] = JSONHelpers.iso(m) }
        if !mediaSubtypes.isEmpty { dict["subtypes"] = mediaSubtypes }
        if let dur = durationSeconds { dict["duration_seconds"] = dur }
        if let lat = latitude, let lon = longitude {
            dict["location"] = ["lat": lat, "lon": lon]
        }
        return dict
    }
}

private struct AlbumRow: Sendable {
    let id: String
    let title: String
    let kind: String
    let count: Int

    func toDictionary() -> [String: Any] {
        ["id": id, "title": title, "kind": kind, "count": count]
    }
}

struct ExportedAsset: Sendable {
    let id: String
    let path: String
    let sizeBytes: Int
    let uti: String

    func toDictionary() -> [String: Any] {
        ["id": id, "path": path, "size_bytes": sizeBytes, "uti": uti]
    }
}

struct PhotoThumbnail: Sendable {
    let data: Data
    let mimeType: String
}

enum PhotosService {
    private static func requestAccess() async throws {
        let status: PHAuthorizationStatus
        if #available(macOS 11.0, *) {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization { cont.resume(returning: $0) }
            }
        }
        switch status {
        case .authorized, .limited: return
        default: throw PhotosError.accessDenied
        }
    }

    static func listAlbums() async throws -> [[String: Any]] {
        try await requestAccess()
        var rows: [AlbumRow] = []

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            rows.append(AlbumRow(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "(untitled)",
                kind: "user",
                count: count
            ))
        }

        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smart.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            rows.append(AlbumRow(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "(untitled)",
                kind: "smart",
                count: count
            ))
        }

        return rows.map { $0.toDictionary() }
    }

    static func search(albumId: String?,
                       after: Date?,
                       before: Date?,
                       favoritesOnly: Bool,
                       mediaType: String?,
                       person: String?,
                       pet: String?,
                       limit: Int) async throws -> [[String: Any]] {
        let identityUUIDs: Set<String>?
        if person != nil || pet != nil {
            try await requestIdentityAccess()
            let database = try PhotosIdentityDB(databaseURL: PhotosIdentityDB.systemDatabaseURL())
            identityUUIDs = try database.assetUUIDs(person: person, pet: pet)
        } else {
            try await requestAccess()
            identityUUIDs = nil
        }

        var predicates: [NSPredicate] = []
        if let d = after {
            predicates.append(NSPredicate(format: "creationDate >= %@", d as NSDate))
        }
        if let d = before {
            predicates.append(NSPredicate(format: "creationDate <= %@", d as NSDate))
        }
        if favoritesOnly {
            predicates.append(NSPredicate(format: "isFavorite == YES"))
        }
        if let mt = mediaType?.lowercased() {
            let typeValue: Int
            switch mt {
            case "image", "photo": typeValue = PHAssetMediaType.image.rawValue
            case "video": typeValue = PHAssetMediaType.video.rawValue
            case "audio": typeValue = PHAssetMediaType.audio.rawValue
            default: typeValue = -1
            }
            if typeValue >= 0 {
                predicates.append(NSPredicate(format: "mediaType == %d", typeValue))
            }
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = identityUUIDs == nil ? limit : 0
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let assets: PHFetchResult<PHAsset>
        if let albumId = albumId {
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId],
                options: nil
            )
            guard let collection = collections.firstObject else {
                throw PhotosError.albumNotFound(albumId)
            }
            assets = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: options)
        }

        if identityUUIDs?.isEmpty == true { return [] }

        var rows: [PhotoRow] = []
        assets.enumerateObjects { asset, _, stop in
            if let identityUUIDs {
                let uuid = String(asset.localIdentifier.prefix(while: { $0 != "/" })).uppercased()
                guard identityUUIDs.contains(uuid) else { return }
            }
            rows.append(PhotoRow(asset))
            if rows.count == limit { stop.pointee = true }
        }
        return rows.map { $0.toDictionary() }
    }

    static func listIdentities(kind: PhotoIdentityKind, query: String?, limit: Int) async throws -> [[String: Any]] {
        try await requestIdentityAccess()
        let database = try PhotosIdentityDB(databaseURL: PhotosIdentityDB.systemDatabaseURL())
        return try database.list(kind: kind, query: query, limit: limit).map { $0.toDictionary() }
    }

    private static func requestIdentityAccess() async throws {
        try await requestAccess()
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw PhotosError.fullAccessRequired
        }
    }

    static func export(id: String, outputPath: String) async throws -> [String: Any] {
        try await requestAccess()
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else {
            throw PhotosError.assetNotFound(id)
        }

        let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        let exported: ExportedAsset
        if asset.mediaType == .video {
            exported = try await exportResource(for: asset, to: url)
        } else {
            exported = try await exportImageData(for: asset, to: url)
        }
        return exported.toDictionary()
    }

    static func viewThumbnail(id: String, maxDimension: Int) async throws -> PhotoThumbnail {
        try await requestAccess()
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = result.firstObject else {
            throw PhotosError.assetNotFound(id)
        }
        guard asset.mediaType == .image else {
            throw PhotosError.unsupportedMediaType(mediaTypeName(asset.mediaType))
        }

        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
        requestOptions.isNetworkAccessAllowed = true

        let target = CGSize(width: maxDimension, height: maxDimension)
        return try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, info in
                if let info = info, let err = info[PHImageErrorKey] as? NSError {
                    cont.resume(throwing: PhotosError.exportFailed(err.localizedDescription))
                    return
                }
                guard let image = image,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpeg = bitmap.representation(
                        using: .jpeg,
                        properties: [.compressionFactor: 0.85]
                      ) else {
                    cont.resume(throwing: PhotosError.exportFailed("Could not encode JPEG"))
                    return
                }
                cont.resume(returning: PhotoThumbnail(data: jpeg, mimeType: "image/jpeg"))
            }
        }
    }

    // MARK: helpers

    fileprivate static func mediaTypeName(_ t: PHAssetMediaType) -> String {
        switch t {
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    fileprivate static func subtypeNames(_ s: PHAssetMediaSubtype) -> [String] {
        var names: [String] = []
        if s.contains(.photoPanorama) { names.append("panorama") }
        if s.contains(.photoHDR) { names.append("hdr") }
        if s.contains(.photoScreenshot) { names.append("screenshot") }
        if s.contains(.photoLive) { names.append("live") }
        if s.contains(.photoDepthEffect) { names.append("portrait") }
        if s.contains(.videoStreamed) { names.append("streamed") }
        if s.contains(.videoHighFrameRate) { names.append("slo-mo") }
        if s.contains(.videoTimelapse) { names.append("timelapse") }
        return names
    }

    private static func exportImageData(for asset: PHAsset, to url: URL) async throws -> ExportedAsset {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        let id = asset.localIdentifier
        let outPath = url.path

        return try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                if let info = info, let err = info[PHImageErrorKey] as? NSError {
                    cont.resume(throwing: PhotosError.exportFailed(err.localizedDescription))
                    return
                }
                guard let data = data else {
                    cont.resume(throwing: PhotosError.exportFailed("No image data returned"))
                    return
                }
                do {
                    try data.write(to: url, options: .atomic)
                    cont.resume(returning: ExportedAsset(
                        id: id,
                        path: outPath,
                        sizeBytes: data.count,
                        uti: uti ?? ""
                    ))
                } catch {
                    cont.resume(throwing: PhotosError.exportFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func exportResource(for asset: PHAsset, to url: URL) async throws -> ExportedAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { r in
            r.type == .video || r.type == .fullSizeVideo
        } ?? resources.first
        guard let resource = primary else {
            throw PhotosError.exportFailed("No exportable resource on asset")
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try? FileManager.default.removeItem(at: url)

        let id = asset.localIdentifier
        let uti = resource.uniformTypeIdentifier
        let outPath = url.path

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: url,
                options: options
            ) { error in
                if let error = error {
                    cont.resume(throwing: PhotosError.exportFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? 0
        return ExportedAsset(id: id, path: outPath, sizeBytes: size, uti: uti)
    }
}
