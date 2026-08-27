import Foundation
import WebKit
import Combine

public final class ShiftMediaSniffer: NSObject, ObservableObject, WKScriptMessageHandler, @unchecked Sendable {
    @Published public var detectedMedia: [SniffedMedia] = []
    
    public static let messageHandlerName = "admMediaSnifferHandler"

    public override init() {
        super.init()
    }

    public static var injectionScript: String {
        return """
        (function() {
            if (window.__admSnifferInstalled) return;
            window.__admSnifferInstalled = true;

            function reportMedia(url, type, title, res, bitrate) {
                if (!url || url.startsWith('blob:http') == false && url.startsWith('http') == false) return;
                try {
                    window.webkit.messageHandlers.admMediaSnifferHandler.postMessage({
                        url: url,
                        type: type || 'video',
                        title: title || document.title || 'Web Media',
                        resolution: res || '',
                        bitrate: bitrate || '',
                        pageUrl: window.location.href
                    });
                } catch(e) {}
            }

            // 1. Sniff HTML5 Video & Audio Elements
            function scanDOMElements() {
                var videos = document.querySelectorAll('video, video source');
                for (var i = 0; i < videos.length; i++) {
                    var v = videos[i];
                    var src = v.src || v.currentSrc;
                    if (src) {
                        var res = (v.videoWidth && v.videoHeight) ? (v.videoWidth + 'x' + v.videoHeight) : '';
                        reportMedia(src, src.includes('.m3u8') ? 'hlsStream' : 'video', document.title, res, '');
                    }
                }
                var audios = document.querySelectorAll('audio, audio source');
                for (var j = 0; j < audios.length; j++) {
                    var a = audios[j];
                    var aSrc = a.src || a.currentSrc;
                    if (aSrc) {
                        reportMedia(aSrc, 'audio', document.title, '', '');
                    }
                }
            }

            // Observe dynamic video/audio additions
            var observer = new MutationObserver(function(mutations) {
                scanDOMElements();
            });
            observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'currentSrc'] });
            scanDOMElements();

            // 2. Intercept Fetch API
            var originalFetch = window.fetch;
            window.fetch = function() {
                var args = arguments;
                var url = (typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url);
                if (url && typeof url === 'string') {
                    if (url.match(/\\.(m3u8|mp4|webm|m4a|mp3|ts|aac|flv|mov|mkv)(\\?|$)/i)) {
                        var type = url.includes('.m3u8') ? 'hlsStream' : (url.match(/\\.(mp3|m4a|aac)(\\?|$)/i) ? 'audio' : 'video');
                        reportMedia(url, type, document.title, '', '');
                    }
                }
                return originalFetch.apply(this, args);
            };

            // 3. Intercept XMLHttpRequest
            var originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (url && typeof url === 'string') {
                    if (url.match(/\\.(m3u8|mp4|webm|m4a|mp3|ts|aac|flv|mov|mkv)(\\?|$)/i)) {
                        var type = url.includes('.m3u8') ? 'hlsStream' : (url.match(/\\.(mp3|m4a|aac)(\\?|$)/i) ? 'audio' : 'video');
                        reportMedia(url, type, document.title, '', '');
                    }
                }
                return originalOpen.apply(this, arguments);
            };
        })();
        """
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let body = message.body as? [String: Any],
              let urlStr = body["url"] as? String,
              let url = URL(string: urlStr),
              let pageUrlStr = body["pageUrl"] as? String,
              let pageUrl = URL(string: pageUrlStr) else {
            return
        }

        let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Media File"
        let resStr = body["resolution"] as? String
        let bitrateStr = body["bitrate"] as? String
        let typeStr = body["type"] as? String ?? "video"

        let mediaType: SniffedMediaType
        let format: String

        if typeStr == "hlsStream" || urlStr.contains(".m3u8") {
            mediaType = .hlsStream
            format = "M3U8"
        } else if typeStr == "audio" || urlStr.contains(".mp3") || urlStr.contains(".m4a") || urlStr.contains(".aac") {
            mediaType = .audio
            format = (url.pathExtension.uppercased().isEmpty ? "MP3" : url.pathExtension.uppercased())
        } else {
            mediaType = .video
            format = (url.pathExtension.uppercased().isEmpty ? "MP4" : url.pathExtension.uppercased())
        }

        let resolution: String? = (resStr != nil && !resStr!.isEmpty) ? resStr : nil
        let bitrate: String? = (bitrateStr != nil && !bitrateStr!.isEmpty) ? bitrateStr : nil

        let sniffed = SniffedMedia(
            url: url,
            pageUrl: pageUrl,
            title: title.isEmpty ? "Media File" : title,
            mediaType: mediaType,
            format: format,
            resolution: resolution,
            bitrate: bitrate
        )

        DispatchQueue.main.async {
            if !self.detectedMedia.contains(where: { $0.url == sniffed.url }) {
                self.detectedMedia.insert(sniffed, at: 0)
                if self.detectedMedia.count > 50 {
                    self.detectedMedia.removeLast()
                }
            }
        }
    }

    public func clear() {
        DispatchQueue.main.async {
            self.detectedMedia.removeAll()
        }
    }
}
