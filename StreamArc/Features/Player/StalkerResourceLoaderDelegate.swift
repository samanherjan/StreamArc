import AVFoundation
import StreamArcCore
import os.log
import UniformTypeIdentifiers

private let loaderLog = Logger(subsystem: "com.samanherjan.streamarc.StreamArc", category: "StalkerLoader")

/// Custom URL scheme used to intercept AVFoundation loading requests for Stalker streams.
/// The scheme replaces `http` → `stalkerhttp` and `https` → `stalkerhttps` so that
/// AVAssetResourceLoader delegates requests to us, allowing injection of the MAG User-Agent
/// and cookie headers that Stalker stream servers require.
let stalkerHTTPScheme = "stalkerhttp"
let stalkerHTTPSScheme = "stalkerhttps"

/// Converts an http(s) URL to use the custom stalker scheme for resource loader interception.
func stalkerCustomSchemeURL(from url: URL) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    if components.scheme == "http" {
        components.scheme = stalkerHTTPScheme
    } else if components.scheme == "https" {
        components.scheme = stalkerHTTPSScheme
    } else {
        return nil
    }
    return components.url
}

/// Restores the original http(s) scheme from a custom stalker URL.
private func originalURL(from customURL: URL) -> URL? {
    guard var components = URLComponents(url: customURL, resolvingAgainstBaseURL: false) else { return nil }
    if components.scheme == stalkerHTTPScheme {
        components.scheme = "http"
    } else if components.scheme == stalkerHTTPSScheme {
        components.scheme = "https"
    } else {
        return nil
    }
    return components.url
}

/// AVAssetResourceLoaderDelegate that proxies HTTP requests for Stalker streams,
/// injecting the MAG User-Agent and Stalker cookies that the stream server requires.
///
/// Without this, AVFoundation uses its default `AppleCoreMedia/...` User-Agent.
/// Many Stalker/MAG servers validate User-Agent and reject requests that don't
/// match the expected MAG STB pattern, returning an HTML error page → -11828.
final class StalkerResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {

    private let config: StalkerClient.Config
    private let session: URLSession

    init(config: StalkerClient.Config) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 3600  // 1 hour for large VOD files
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let requestURL = loadingRequest.request.url,
              let realURL = originalURL(from: requestURL) else {
            return false
        }

        loaderLog.debug("🔀 StalkerLoader: \(realURL.absoluteString.prefix(150), privacy: .public)")

        var request = URLRequest(url: realURL)
        // For cross-origin CDN servers (different host from portal), use KSPlayer UA
        // as per iptvnator's stalker-live-playback.utils.ts. For same-origin (portal host),
        // use the MAG User-Agent.
        let portalHost = URL(string: config.portalURL)?.host ?? ""
        let isCrossOrigin = realURL.host != portalHost && !portalHost.isEmpty
        if isCrossOrigin {
            request.setValue("KSPlayer", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        } else {
            request.setValue(config.magUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(config.stalkerCookie, forHTTPHeaderField: "Cookie")
        }

        // Forward range requests from AVFoundation (for seeking in large files)
        if let dataRequest = loadingRequest.dataRequest {
            let offset = dataRequest.requestedOffset
            if dataRequest.requestsAllDataToEndOfResource {
                request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
            } else {
                let end = offset + Int64(dataRequest.requestedLength) - 1
                request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            }
        }

        let task = session.dataTask(with: request) { [weak loadingRequest] data, response, error in
            guard let loadingRequest = loadingRequest else { return }

            if let error = error {
                loaderLog.error("❌ StalkerLoader error: \(error.localizedDescription, privacy: .public)")
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: URLError(.badServerResponse))
                return
            }

            loaderLog.debug("📡 StalkerLoader response: HTTP \(httpResponse.statusCode), mime=\(httpResponse.mimeType ?? "nil", privacy: .public), length=\(httpResponse.expectedContentLength)")

            // Check for HTML error responses (server rejected the request)
            if let mimeType = httpResponse.mimeType, mimeType.contains("text/html") {
                loaderLog.error("❌ StalkerLoader: server returned HTML — likely auth/UA rejection. Status=\(httpResponse.statusCode)")
                if let data = data, let body = String(data: data.prefix(500), encoding: .utf8) {
                    loaderLog.error("❌ HTML body: \(body, privacy: .public)")
                }
                loadingRequest.finishLoading(with: URLError(.userAuthenticationRequired))
                return
            }

            guard (200...399).contains(httpResponse.statusCode) else {
                loaderLog.error("❌ StalkerLoader: HTTP \(httpResponse.statusCode)")
                loadingRequest.finishLoading(with: URLError(.badServerResponse))
                return
            }

            guard let data = data, !data.isEmpty else {
                loadingRequest.finishLoading(with: URLError(.zeroByteResource))
                return
            }

            // Fill content information
            if let contentInfo = loadingRequest.contentInformationRequest {
                let mimeType = httpResponse.mimeType ?? "video/x-matroska"
                if let uti = UTType(mimeType: mimeType)?.identifier {
                    contentInfo.contentType = uti
                } else {
                    contentInfo.contentType = "public.movie"
                }

                if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                    // Parse "bytes 0-999/5000" format
                    if let totalStr = contentRange.split(separator: "/").last,
                       let total = Int64(totalStr), total > 0 {
                        contentInfo.contentLength = total
                    }
                } else if httpResponse.expectedContentLength > 0 {
                    contentInfo.contentLength = httpResponse.expectedContentLength
                }

                contentInfo.isByteRangeAccessSupported = true
            }

            // Deliver data
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()

            loaderLog.debug("✅ StalkerLoader delivered \(data.count) bytes")
        }
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // No-op; URLSession tasks will complete/cancel naturally
    }
}
