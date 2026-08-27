import Foundation

public enum URLProtocolType: String, Codable, Sendable {
    case http = "HTTP"
    case https = "HTTPS"
    case bittorrent = "BitTorrent"
    case magnet = "Magnet"
    case hls = "HLS Stream"
    case googleDrive = "Google Drive"
    case dropbox = "Dropbox"
    case githubRelease = "GitHub Release"
    case mediafire = "MediaFire"
    case onedrive = "OneDrive"
    case internetArchive = "Internet Archive"
    case unknown = "Unknown"
}

public struct URLProbeMetadata: Sendable {
    public let originalURL: URL
    public let resolvedDirectURL: URL
    public let protocolType: URLProtocolType
    public let fileName: String?
    public let fileSize: Int64
    public let supportsRanges: Bool
    public let mimeType: String?
    public let etag: String?
    public let customHeaders: [String: String]

    public init(
        originalURL: URL,
        resolvedDirectURL: URL,
        protocolType: URLProtocolType,
        fileName: String? = nil,
        fileSize: Int64 = -1,
        supportsRanges: Bool = false,
        mimeType: String? = nil,
        etag: String? = nil,
        customHeaders: [String: String] = [:]
    ) {
        self.originalURL = originalURL
        self.resolvedDirectURL = resolvedDirectURL
        self.protocolType = protocolType
        self.fileName = fileName
        self.fileSize = fileSize
        self.supportsRanges = supportsRanges
        self.mimeType = mimeType
        self.etag = etag
        self.customHeaders = customHeaders
    }
}

public enum MIMETypeRegistry {
    private static let mimeToExtension: [String: String] = [
        // Video
        "video/mp4": "mp4",
        "video/x-matroska": "mkv",
        "video/webm": "webm",
        "video/quicktime": "mov",
        "video/x-msvideo": "avi",
        "video/x-flv": "flv",
        "video/3gpp": "3gp",
        "video/mp2t": "ts",
        "application/x-mpegurl": "m3u8",
        "application/vnd.apple.mpegurl": "m3u8",

        // Audio
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3",
        "audio/aac": "aac",
        "audio/x-m4a": "m4a",
        "audio/flac": "flac",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/ogg": "ogg",
        "audio/webm": "weba",

        // Documents
        "application/pdf": "pdf",
        "application/msword": "doc",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
        "application/vnd.ms-excel": "xls",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
        "application/vnd.ms-powerpoint": "ppt",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
        "text/plain": "txt",
        "text/html": "html",
        "text/markdown": "md",
        "application/json": "json",
        "application/xml": "xml",
        "text/xml": "xml",
        "application/epub+zip": "epub",

        // Compressed Archives
        "application/zip": "zip",
        "application/x-zip-compressed": "zip",
        "application/x-rar-compressed": "rar",
        "application/x-rar": "rar",
        "application/x-7z-compressed": "7z",
        "application/x-tar": "tar",
        "application/gzip": "tar.gz",
        "application/x-gzip": "tar.gz",
        "application/x-bzip2": "tar.bz2",
        "application/x-xz": "tar.xz",

        // Applications & Disk Images
        "application/vnd.android.package-archive": "apk",
        "application/x-apple-diskimage": "dmg",
        "application/x-iso9660-image": "iso",
        "application/octet-stream": "bin",
        "application/x-msdos-program": "exe",
        "application/x-msi": "msi",
        "application/x-debian-package": "deb",
        "application/x-redhat-package-manager": "rpm",
        "application/x-bittorrent": "torrent",

        // Images
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/svg+xml": "svg",
        "image/bmp": "bmp",
        "image/tiff": "tiff",
        "image/heic": "heic"
    ]

    public static func extensionForMIMEType(_ mime: String) -> String? {
        let clean = mime.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? mime.lowercased()
        return mimeToExtension[clean]
    }
}

public enum AdvancedContentDispositionParser {
    public static func extractFileName(from disposition: String) -> String? {
        // 1. RFC 5987 / RFC 6266 filename*=charset'lang'encoded_value
        if let range = disposition.range(of: #"filename\*=([^\']+)\'([^\']*)\'([^;\r\n]+)"#, options: .regularExpression) {
            let matched = String(disposition[range])
            let parts = matched.components(separatedBy: "'")
            if parts.count >= 3 {
                let charset = parts[0].replacingOccurrences(of: "filename*=", with: "").trimmingCharacters(in: .whitespaces)
                let encoded = parts.dropFirst(2).joined(separator: "'").trimmingCharacters(in: .whitespaces)
                if let decoded = decodePercentEncodedString(encoded, charset: charset) {
                    let cleaned = sanitize(decoded)
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }

        // 2. Quoted filename="my file.zip"
        if let range = disposition.range(of: #"filename=\"([^\"]+)\""#, options: .regularExpression) {
            let matched = String(disposition[range])
            let name = matched.replacingOccurrences(of: "filename=\"", with: "").replacingOccurrences(of: "\"", with: "")
            let cleaned = sanitize(name)
            if !cleaned.isEmpty { return cleaned }
        }

        // 3. Unquoted filename=myfile.zip
        if let range = disposition.range(of: #"filename=([^;\r\n]+)"#, options: .regularExpression) {
            let matched = String(disposition[range])
            let name = matched.replacingOccurrences(of: "filename=", with: "").trimmingCharacters(in: .whitespaces)
            let cleaned = sanitize(name)
            if !cleaned.isEmpty { return cleaned }
        }

        return nil
    }

    public static func decodePercentEncodedString(_ encoded: String, charset: String) -> String? {
        // 1. Try standard UTF-8 first
        if let utf8Decoded = encoded.removingPercentEncoding {
            return utf8Decoded
        }

        // 2. Parse raw bytes from %XX sequences
        var data = Data()
        var i = encoded.startIndex
        while i < encoded.endIndex {
            if encoded[i] == "%" {
                let next1 = encoded.index(after: i)
                if next1 < encoded.endIndex {
                    let next2 = encoded.index(after: next1)
                    if next2 < encoded.endIndex {
                        let hexStr = String(encoded[next1...next2])
                        if let byte = UInt8(hexStr, radix: 16) {
                            data.append(byte)
                            i = encoded.index(after: next2)
                            continue
                        }
                    }
                }
            }
            if let asciiByte = encoded[i].asciiValue {
                data.append(asciiByte)
            }
            i = encoded.index(after: i)
        }

        // Try decoding with specified charset
        let upperCharset = charset.uppercased()
        if upperCharset.contains("GBK") || upperCharset.contains("GB2312") || upperCharset.contains("GB18030") {
            let cfEnc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let str = String(data: data, encoding: String.Encoding(rawValue: cfEnc)) {
                return str
            }
        }
        if upperCharset.contains("ISO-8859-1") || upperCharset.contains("LATIN1") {
            if let str = String(data: data, encoding: .isoLatin1) {
                return str
            }
        }
        if upperCharset.contains("WINDOWS-1252") {
            if let str = String(data: data, encoding: .windowsCP1252) {
                return str
            }
        }

        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? encoded
    }

    public static func sanitize(_ rawName: String) -> String {
        var clean = rawName
        // Unescape HTML entities (Gopeed #1215)
        clean = clean.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        // Unescape URL percent encoding if leftover (e.g. %20 -> space)
        if let unescaped = clean.removingPercentEncoding {
            clean = unescaped
        }

        // Strip path traversal and invalid OS characters
        clean = clean.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.hasPrefix("\"") && clean.hasSuffix("\"") && clean.count > 1 {
            clean = String(clean.dropFirst().dropLast())
        }
        return clean
    }
}

public enum UniversalURLResolver {

    /// Classifies URL into appropriate protocol / service handler
    public static func detectProtocolType(for url: URL) -> URLProtocolType {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        if scheme == "magnet" || url.absoluteString.hasPrefix("magnet:?") {
            return .magnet
        }
        if path.hasSuffix(".torrent") {
            return .bittorrent
        }
        if path.hasSuffix(".m3u8") {
            return .hls
        }
        if host.contains("drive.google.com") || host.contains("docs.google.com") || host.contains("drive.usercontent.google.com") {
            return .googleDrive
        }
        if host.contains("dropbox.com") {
            return .dropbox
        }
        if host.contains("github.com") && path.contains("/releases/download/") {
            return .githubRelease
        }
        if host.contains("mediafire.com") {
            return .mediafire
        }
        if host.contains("archive.org") {
            return .internetArchive
        }
        if host.contains("1drv.ms") || host.contains("onedrive.live.com") || host.contains("sharepoint.com") {
            return .onedrive
        }
        if scheme == "https" {
            return .https
        }
        if scheme == "http" {
            return .http
        }
        return .unknown
    }

    /// Transforms sharing / cloud URLs into direct download streams (like Gopeed resolvers)
    public static func transformToDirectURL(_ url: URL) -> URL {
        let str = url.absoluteString
        let host = url.host?.lowercased() ?? ""

        // 1. Dropbox: ?dl=0 -> ?dl=1
        if host.contains("dropbox.com") {
            if str.contains("?dl=0") {
                return URL(string: str.replacingOccurrences(of: "?dl=0", with: "?dl=1")) ?? url
            } else if !str.contains("?dl=1") && !str.contains("&dl=1") {
                let separator = str.contains("?") ? "&" : "?"
                return URL(string: str + "\(separator)dl=1") ?? url
            }
        }

        // 2. GitHub raw/releases
        if host == "github.com" && str.contains("/raw/") {
            let direct = str.replacingOccurrences(of: "github.com", with: "raw.githubusercontent.com")
                .replacingOccurrences(of: "/raw/", with: "/")
            return URL(string: direct) ?? url
        }

        return url
    }

    /// Complete universal probe & resolution pipeline (Gopeed Architecture)
    public static func resolveURL(
        _ url: URL,
        customHeaders: [String: String] = [:],
        userAgent: String? = nil
    ) async throws -> URLProbeMetadata {
        let protoType = detectProtocolType(for: url)

        // 1. Google Drive Dedicated Resolver
        if protoType == .googleDrive {
            if let driveRes = try? await GoogleDriveURLResolver.resolveGoogleDriveURL(url) {
                return URLProbeMetadata(
                    originalURL: url,
                    resolvedDirectURL: driveRes.directURL,
                    protocolType: .googleDrive,
                    fileName: driveRes.fileName,
                    fileSize: driveRes.fileSize,
                    supportsRanges: true,
                    mimeType: driveRes.mimeType,
                    etag: nil,
                    customHeaders: driveRes.customHeaders
                )
            }
        }

        // 2. Direct transformation for Dropbox, GitHub, etc.
        let directURL = transformToDirectURL(url)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 10.0
        config.httpShouldSetCookies = true
        let session = URLSession(configuration: config)

        var getReq = URLRequest(url: directURL)
        getReq.httpMethod = "GET"
        getReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        getReq.setValue(userAgent ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        getReq.setValue("*/*", forHTTPHeaderField: "Accept")
        for (k, v) in customHeaders { getReq.setValue(v, forHTTPHeaderField: k) }

        var finalResponse: HTTPURLResponse? = nil

        if let (_, response) = try? await session.data(for: getReq),
           let http = response as? HTTPURLResponse {
            finalResponse = http
        } else {
            var headReq = URLRequest(url: directURL)
            headReq.httpMethod = "HEAD"
            headReq.setValue(userAgent ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            headReq.setValue("*/*", forHTTPHeaderField: "Accept")
            for (k, v) in customHeaders { headReq.setValue(v, forHTTPHeaderField: k) }

            if let (_, response) = try? await session.data(for: headReq),
               let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                finalResponse = http
            }
        }

        guard let http = finalResponse else {
            // Fallback from URL pathname
            let defaultName = extractFileNameFromURL(directURL)
            return URLProbeMetadata(
                originalURL: url,
                resolvedDirectURL: directURL,
                protocolType: protoType,
                fileName: defaultName,
                fileSize: -1,
                supportsRanges: false,
                mimeType: nil,
                etag: nil
            )
        }

        var fileSize: Int64 = -1
        var supportsRanges = false
        var fileName: String? = nil
        let mimeType = http.mimeType
        let etag = ChunkedDownloader.getHeader("ETag", from: http)

        if let acceptRanges = ChunkedDownloader.getHeader("Accept-Ranges", from: http), acceptRanges.lowercased().contains("bytes") {
            supportsRanges = true
        }

        if let contentRange = ChunkedDownloader.getHeader("Content-Range", from: http) {
            supportsRanges = true
            if let slashIndex = contentRange.lastIndex(of: "/") {
                let totalStr = String(contentRange[contentRange.index(after: slashIndex)...])
                if let parsed = Int64(totalStr.trimmingCharacters(in: .whitespaces)) {
                    fileSize = parsed
                }
            }
        } else if let contentLengthStr = ChunkedDownloader.getHeader("Content-Length", from: http), let parsed = Int64(contentLengthStr) {
            fileSize = parsed
        }

        if fileSize <= 0 && http.expectedContentLength > 0 {
            fileSize = http.expectedContentLength
        }

        // Parse Content-Disposition Header (Gopeed algorithm)
        if let disposition = ChunkedDownloader.getHeader("Content-Disposition", from: http) {
            fileName = AdvancedContentDispositionParser.extractFileName(from: disposition)
        }

        // If no filename in header, extract from URL pathname
        if fileName == nil || fileName?.isEmpty == true {
            fileName = extractFileNameFromURL(http.url ?? directURL)
        }

        // If filename is missing extension, try MIMETypeRegistry
        if let currentName = fileName, !currentName.contains("."), let mime = mimeType {
            if let ext = MIMETypeRegistry.extensionForMIMEType(mime) {
                fileName = "\(currentName).\(ext)"
            }
        }

        let finalDirectURL = http.url ?? directURL

        return URLProbeMetadata(
            originalURL: url,
            resolvedDirectURL: finalDirectURL,
            protocolType: protoType,
            fileName: fileName,
            fileSize: fileSize,
            supportsRanges: supportsRanges,
            mimeType: mimeType,
            etag: etag
        )
    }

    private static func extractFileNameFromURL(_ url: URL) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty && last != "/" {
            let clean = last.components(separatedBy: "?").first ?? last
            if let unescaped = clean.removingPercentEncoding {
                return AdvancedContentDispositionParser.sanitize(unescaped)
            }
            return AdvancedContentDispositionParser.sanitize(clean)
        }
        return "download_\(Int(Date().timeIntervalSince1970))"
    }
}
