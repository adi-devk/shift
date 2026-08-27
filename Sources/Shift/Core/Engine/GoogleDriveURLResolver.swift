import Foundation

public struct ResolvedDownloadTarget: Sendable {
    public let originalURL: URL
    public let directURL: URL
    public let fileName: String?
    public let fileSize: Int64
    public let mimeType: String?
    public let customHeaders: [String: String]

    public init(
        originalURL: URL,
        directURL: URL,
        fileName: String? = nil,
        fileSize: Int64 = -1,
        mimeType: String? = nil,
        customHeaders: [String: String] = [:]
    ) {
        self.originalURL = originalURL
        self.directURL = directURL
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.customHeaders = customHeaders
    }
}

public enum ContentDispositionParser {
    public static func extractFileName(from disposition: String) -> String? {
        // 1. Try RFC 5987 / RFC 6266 filename*=UTF-8''encoded_name
        if let range = disposition.range(of: "filename\\*=(?:UTF-8|utf-8)''([^;\\r\\n]+)", options: .regularExpression) {
            let matched = String(disposition[range])
            let prefixLen = matched.hasPrefix("filename*=UTF-8''") ? "filename*=UTF-8''".count : "filename*=utf-8''".count
            let encoded = String(matched.dropFirst(prefixLen)).trimmingCharacters(in: .whitespaces)
            if let decoded = encoded.removingPercentEncoding {
                let cleaned = sanitizeFileName(decoded)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        // 2. Try quoted filename="name.ext"
        if let range = disposition.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
            let matched = String(disposition[range])
            let name = matched.replacingOccurrences(of: "filename=\"", with: "").replacingOccurrences(of: "\"", with: "")
            let cleaned = sanitizeFileName(name)
            if !cleaned.isEmpty { return cleaned }
        }

        // 3. Try unquoted filename=name.ext
        if let range = disposition.range(of: "filename=([^;\\r\\n]+)", options: .regularExpression) {
            let matched = String(disposition[range])
            let name = matched.replacingOccurrences(of: "filename=", with: "").trimmingCharacters(in: .whitespaces)
            let cleaned = sanitizeFileName(name)
            if !cleaned.isEmpty { return cleaned }
        }

        return nil
    }

    public static func sanitizeFileName(_ rawName: String) -> String {
        var clean = rawName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove surrounding quotes if any
        if clean.hasPrefix("\"") && clean.hasSuffix("\"") && clean.count > 1 {
            clean = String(clean.dropFirst().dropLast())
        }
        return clean
    }
}

public enum GoogleDriveURLResolver {
    /// Detects if a URL is a Google Drive file link
    public static func isGoogleDriveURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host.contains("drive.google.com") || host.contains("docs.google.com") || host.contains("drive.usercontent.google.com") {
            return extractFileID(from: url) != nil
        }
        return false
    }

    /// Extracts Google Drive File ID from various link formats
    public static func extractFileID(from url: URL) -> String? {
        let str = url.absoluteString

        // Format 1: /file/d/FILE_ID/...
        if let range = str.range(of: #"/file/d/([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let match = String(str[range])
            let id = match.replacingOccurrences(of: "/file/d/", with: "")
            if !id.isEmpty { return id }
        }

        // Format 2: ?id=FILE_ID or &id=FILE_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            if let idItem = items.first(where: { $0.name == "id" }), let val = idItem.value, !val.isEmpty {
                return val
            }
        }

        // Format 3: /uc?id=FILE_ID or /open?id=FILE_ID
        if let range = str.range(of: #"[?&]id=([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
            let match = String(str[range])
            let id = match.replacingOccurrences(of: "?id=", with: "").replacingOccurrences(of: "&id=", with: "")
            if !id.isEmpty { return id }
        }

        return nil
    }

    /// Resolves any Google Drive sharing link to a direct streaming URL and extracts the real file name and size
    public static func resolveGoogleDriveURL(_ url: URL) async throws -> ResolvedDownloadTarget {
        guard let fileID = extractFileID(from: url) else {
            throw NSError(domain: "GoogleDriveURLResolver", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Google Drive link or File ID not found."])
        }

        ShiftLogger.shared.info("🔍 Resolving Google Drive File ID: \(fileID)", category: .network)

        // Standard direct export URL
        let exportURL = URL(string: "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&confirm=t")!

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20.0
        let session = URLSession(configuration: config)

        var request = URLRequest(url: exportURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://drive.google.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return ResolvedDownloadTarget(originalURL: url, directURL: exportURL, fileName: nil, fileSize: -1)
        }

        // Check Content-Disposition on the direct response
        var resolvedFileName: String? = nil
        if let disposition = httpResponse.allHeaderFields["Content-Disposition"] as? String ?? httpResponse.allHeaderFields["content-disposition"] as? String {
            resolvedFileName = ContentDispositionParser.extractFileName(from: disposition)
        }

        var fileSize: Int64 = httpResponse.expectedContentLength
        let mimeType = httpResponse.mimeType

        // If Google returned an HTML page (virus scan warning or interstitial), find the direct stream URL
        if let mime = mimeType, mime.contains("text/html") {
            let html = String(data: data, encoding: .utf8) ?? ""

            // Look for "Download anyway" link / form
            // e.g. <a id="uc-download-link" href="https://drive.usercontent.google.com/download?id=...&export=download&confirm=...&uuid=...">
            if let downloadLinkRange = html.range(of: #"href="([^"]*drive\.usercontent\.google\.com\/download[^"]*)""#, options: .regularExpression) {
                let matched = String(html[downloadLinkRange])
                let linkStr = matched.replacingOccurrences(of: "href=\"", with: "").replacingOccurrences(of: "\"", with: "")
                let decodedLink = linkStr.replacingOccurrences(of: "&amp;", with: "&")
                if let directURL = URL(string: decodedLink) {
                    ShiftLogger.shared.info("✅ Found Google Drive confirmation bypass URL: \(directURL)", category: .network)

                    // Probe direct URL with byte range to obtain exact total file size and Content-Disposition
                    let probe = await probeDirectStreamURL(directURL, session: session)
                    let finalName = resolvedFileName ?? probe.fileName ?? extractFileNameFromDriveHTML(html)
                    let finalSize = probe.fileSize > 0 ? probe.fileSize : fileSize

                    return ResolvedDownloadTarget(
                        originalURL: url,
                        directURL: directURL,
                        fileName: finalName,
                        fileSize: finalSize,
                        mimeType: probe.mimeType ?? "application/octet-stream"
                    )
                }
            }

            // Look for confirm token e.g. name="confirm" value="t" or confirm=XXXX
            if let confirmRange = html.range(of: #"confirm=([a-zA-Z0-9_-]+)"#, options: .regularExpression) {
                let matched = String(html[confirmRange])
                let token = matched.replacingOccurrences(of: "confirm=", with: "")
                let bypassURL = URL(string: "https://drive.usercontent.google.com/download?id=\(fileID)&export=download&confirm=\(token)")!

                let probe = await probeDirectStreamURL(bypassURL, session: session)
                let finalName = resolvedFileName ?? probe.fileName ?? extractFileNameFromDriveHTML(html)
                let finalSize = probe.fileSize > 0 ? probe.fileSize : fileSize

                return ResolvedDownloadTarget(
                    originalURL: url,
                    directURL: bypassURL,
                    fileName: finalName,
                    fileSize: finalSize,
                    mimeType: probe.mimeType ?? "application/octet-stream"
                )
            }

            if resolvedFileName == nil {
                resolvedFileName = extractFileNameFromDriveHTML(html)
            }
        }

        // If direct response had the file, probe for exact size
        let finalDirectURL = httpResponse.url ?? exportURL
        let directProbe = await probeDirectStreamURL(finalDirectURL, session: session)
        let finalName = resolvedFileName ?? directProbe.fileName
        let finalSize = directProbe.fileSize > 0 ? directProbe.fileSize : (fileSize > 0 ? fileSize : -1)

        return ResolvedDownloadTarget(
            originalURL: url,
            directURL: finalDirectURL,
            fileName: finalName,
            fileSize: finalSize,
            mimeType: directProbe.mimeType ?? mimeType
        )
    }

    private static func probeDirectStreamURL(_ directURL: URL, session: URLSession) async -> (fileSize: Int64, fileName: String?, mimeType: String?) {
        var req = URLRequest(url: directURL)
        req.httpMethod = "GET"
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse else {
            return (-1, nil, nil)
        }

        var size: Int64 = -1
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? (http.allHeaderFields["Content-Range"] as? String) {
            if let slashIdx = contentRange.lastIndex(of: "/") {
                let sub = String(contentRange[contentRange.index(after: slashIdx)...]).trimmingCharacters(in: .whitespaces)
                if let parsed = Int64(sub) {
                    size = parsed
                }
            }
        } else if let len = http.value(forHTTPHeaderField: "Content-Length") ?? (http.allHeaderFields["Content-Length"] as? String), let parsed = Int64(len) {
            size = parsed
        }

        var name: String? = nil
        if let disp = http.value(forHTTPHeaderField: "Content-Disposition") ?? (http.allHeaderFields["Content-Disposition"] as? String) {
            name = ContentDispositionParser.extractFileName(from: disp)
        }

        return (size, name, http.mimeType)
    }

    private static func extractFileNameFromDriveHTML(_ html: String) -> String? {
        // Try title tag: <title>FILENAME - Google Drive</title>
        if let titleRange = html.range(of: #"<title>(.*?) - Google Drive<\/title>"#, options: .regularExpression) {
            let matched = String(html[titleRange])
            let title = matched.replacingOccurrences(of: "<title>", with: "").replacingOccurrences(of: " - Google Drive</title>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && title != "Google Drive" {
                return ContentDispositionParser.sanitizeFileName(title)
            }
        }

        // Try item name span: <span class="uc-name-size"><a ...>FILENAME</a>
        if let nameRange = html.range(of: #"class="uc-name-size"[^>]*><a[^>]*>(.*?)<\/a>"#, options: .regularExpression) {
            let matched = String(html[nameRange])
            if let textRange = matched.range(of: #">(.*?)<\/a>"#, options: .regularExpression) {
                let inner = String(matched[textRange]).replacingOccurrences(of: ">", with: "").replacingOccurrences(of: "</a>", with: "")
                if !inner.isEmpty {
                    return ContentDispositionParser.sanitizeFileName(inner)
                }
            }
        }

        return nil
    }
}
