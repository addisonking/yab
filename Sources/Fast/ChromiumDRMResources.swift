import Foundation
import WebKit
import YabCoreClient

/// A Chromium extension's pages, served into a WebKit tab's frames. The DRM
/// bridge replays an extension's content scripts on a WebKit page, and their
/// overlays (Bitwarden's inline menu, 1Password's) are iframes and fetches
/// pointing at chrome-extension:// addresses, a scheme WebKit serves nothing
/// for: the frames mounted empty and the menu never rendered. The bytes come
/// from the same native read the content scripts use (ext.bridge.files: the
/// profile's catalog, an extension enabled there, a file under its own root,
/// size capped), and only what the extension declared web-accessible reaches
/// a page, and only from the origins it listed. An extension's own pages can
/// chain freely; a page can never take a frame or a file it was not offered.
@available(macOS 15.4, *)
@MainActor
final class ChromiumDRMResources: NSObject, WKURLSchemeHandler {
    static let shared = ChromiumDRMResources()
    private var stopped: Set<ObjectIdentifier> = []

    nonisolated func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        Task { @MainActor in await serve(webView, task) }
    }
    nonisolated func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        Task { @MainActor in stopped.insert(ObjectIdentifier(task)) }
    }
    private func live(_ task: WKURLSchemeTask) -> Bool { !stopped.contains(ObjectIdentifier(task)) }

    private func serve(_ webView: WKWebView, _ task: WKURLSchemeTask) async {
        guard let url = task.request.url, url.scheme?.lowercased() == "chrome-extension", let id = url.host, !id.isEmpty,
              url.path.count > 1, !url.path.contains("..") else { return fail(task) }
        let path = String(url.path.dropFirst())
        // The page embedding the frame. A main frame is its own document, and
        // main frames are not served here: a page can't walk itself into an
        // extension's pages, the way Chrome refuses the web that address.
        guard let page = task.request.mainDocumentURL ?? webView.url, page != url,
              let tab = Extensions.shared.tab(showing: webView), let bridge = tab.chromiumDRMExtensions,
              let entry = bridge.entries[id], let manifest = entry["manifest"] as? [String: Any] else { return fail(task) }
        let session = bridge.session
        if page.scheme?.lowercased() == "chrome-extension" {
            // One of the extension's own pages chaining to another.
            guard page.host == id else { return fail(task) }
        } else {
            guard ["http", "https"].contains(page.scheme?.lowercased() ?? "") else { return fail(task) }
            var accessible = false
            for group in manifest["web_accessible_resources"] as? [[String: Any]] ?? [] {
                let resources = group["resources"] as? [String] ?? [], matches = group["matches"] as? [String] ?? []
                if matches.contains(where: { ChromiumDRMExtensionScripts.matches($0, url: page) }),
                   resources.contains(where: { Self.pattern($0, covers: path) }) { accessible = true; break }
            }
            guard accessible else { return fail(task) }
        }
        guard let reply = try? await session.request("ext.bridge.files", ["extension": id, "files": [path]]),
              let source = reply[path].string, !source.isEmpty, live(task) else { return fail(task) }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                             headerFields: ["Content-Type": Self.mime(path), "Access-Control-Allow-Origin": "*"]),
              live(task) else { return fail(task) }
        task.didReceive(response)
        guard live(task) else { return }
        task.didReceive(Data(source.utf8))
        if live(task) { task.didFinish() }
    }
    private func fail(_ task: WKURLSchemeTask) {
        guard live(task) else { return }
        task.didFailWithError(YabCoreError.remote("Extension resource is unavailable to this page"))
        stopped.insert(ObjectIdentifier(task))
    }
    /// A web-accessible entry's pattern: `*` covers the rest of the path
    /// between what the entry says before and after it.
    static func pattern(_ value: String, covers path: String) -> Bool {
        guard let star = value.firstIndex(of: "*") else { return value == path }
        var head = String(value[..<star])
        if head.hasPrefix("/") { head = String(head.dropFirst()) }
        let tail = String(value[value.index(after: star)...])
        return path.hasPrefix(head) && path.hasSuffix(tail) && path.count > head.count + tail.count
    }
    private static func mime(_ path: String) -> String {
        let kind = (path as NSString).pathExtension.lowercased()
        let known = [
            "html": "text/html", "js": "text/javascript", "mjs": "text/javascript", "css": "text/css",
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "svg": "image/svg+xml", "webp": "image/webp", "ico": "image/x-icon", "json": "application/json",
            "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf", "otf": "font/otf", "txt": "text/plain",
        ]
        let type = known[kind] ?? "application/octet-stream"
        return type.hasPrefix("text/") || type == "application/json" ? type + "; charset=utf-8" : type
    }
}
