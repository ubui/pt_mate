#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

final class WebDebugService: @unchecked Sendable {
    static let shared = WebDebugService()

    private struct ServerFailure: Error, CustomStringConvertible {
        let message: String

        var description: String {
            message
        }
    }

    private struct RequestFailure: Error, CustomStringConvertible {
        let message: String

        var description: String {
            message
        }
    }

    private struct Request {
        let method: String
        let path: String
        let body: Data
    }

    private struct Response {
        let status: Int
        let contentType: String?
        let body: Data
    }

    private let lock = NSLock()
    private var listenerValue: Int32 = -1
    private var hostUrlsValue: [String] = []

    private init() {}

    var isRunning: Bool {
        withLock { listenerValue >= 0 }
    }

    var hostUrls: [String] {
        withLock { hostUrlsValue }
    }

    var hostUrl: String {
        hostUrls.first ?? ""
    }

    func start(port: UInt16 = 8833) async -> Bool {
        startServer(port: port)
    }

    func stop() async {
        stopServer()
    }

    private func startServer(port: UInt16) -> Bool {
        lock.lock()
        if listenerValue >= 0 {
            lock.unlock()
            return true
        }

        let descriptor: Int32
        do {
            descriptor = try Self.openListener(port: port)
        } catch {
            do {
                descriptor = try Self.openListener(port: 0)
            } catch {
                listenerValue = -1
                hostUrlsValue = []
                lock.unlock()
                return false
            }
        }

        let boundPort = Self.boundPort(of: descriptor) ?? Int(port)
        var urls = Self.pickLanIPv4().map { "http://\($0):\(boundPort)/" }
        if urls.isEmpty {
            urls = ["http://127.0.0.1:\(boundPort)/"]
        }

        listenerValue = descriptor
        hostUrlsValue = urls
        lock.unlock()

        spawnConnectionWorker(descriptor)
        return true
    }

    private func stopServer() {
        lock.lock()
        let descriptor = listenerValue
        listenerValue = -1
        hostUrlsValue = []
        lock.unlock()

        if descriptor >= 0 {
            close(descriptor)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static let streamSocketType: Int32 = {
        #if canImport(Darwin)
        return SOCK_STREAM
        #else
        return Int32(truncatingIfNeeded: SOCK_STREAM.rawValue)
        #endif
    }()

    private static let sendFlags: Int32 = {
        #if canImport(Darwin)
        return 0
        #else
        return Int32(MSG_NOSIGNAL)
        #endif
    }()

    private static func openListener(port: UInt16) throws -> Int32 {
        let descriptor = socket(AF_INET, streamSocketType, 0)
        guard descriptor >= 0 else {
            throw ServerFailure(message: "socket_failed")
        }
        var reuse: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 || listen(descriptor, 128) != 0 {
            close(descriptor)
            throw ServerFailure(message: "bind_failed")
        }
        return descriptor
    }

    private static func boundPort(of descriptor: Int32) -> Int? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard result == 0 else {
            return nil
        }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private static func pickLanIPv4() -> [String] {
        var ips: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else {
            return ips.isEmpty ? ["127.0.0.1"] : ips
        }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr else {
                continue
            }
            guard address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let interfaceName = String(cString: current.pointee.ifa_name)
            if interfaceName == "lo0" || interfaceName == "lo" {
                continue
            }
            var sinAddress = address.withMemoryRebound(
                to: sockaddr_in.self,
                capacity: 1
            ) { $0.pointee.sin_addr }
            if sinAddress.s_addr == INADDR_ANY {
                continue
            }
            let textBuffer = UnsafeMutablePointer<CChar>.allocate(
                capacity: Int(INET_ADDRSTRLEN)
            )
            defer { textBuffer.deallocate() }
            guard
                let value = inet_ntop(
                    AF_INET,
                    &sinAddress,
                    textBuffer,
                    socklen_t(INET_ADDRSTRLEN)
                )
            else {
                continue
            }
            ips.append(String(cString: value))
        }
        return ips.isEmpty ? ["127.0.0.1"] : ips
    }

    private func spawnConnectionWorker(_ descriptor: Int32) {
        let thread = Thread { [weak self] in
            self?.acceptLoop(descriptor)
        }
        thread.name = "com.ptmate.webdebug.accept"
        thread.start()
    }

    private func acceptLoop(_ descriptor: Int32) {
        while true {
            guard withLock({ listenerValue == descriptor }) else {
                return
            }
            let connection = Self.acceptConnection(on: descriptor)
            if connection < 0 {
                if withLock({ listenerValue == descriptor }) {
                    let code = errno
                    if code == EINTR || code == EAGAIN {
                        continue
                    }
                }
                return
            }
            let worker = Thread { [weak self] in
                let finished = DispatchSemaphore(value: 0)
                Task {
                    await self?.serve(connection)
                    finished.signal()
                }
                finished.wait()
            }
            worker.name = "com.ptmate.webdebug.connection"
            worker.start()
        }
    }

    private static func acceptConnection(on descriptor: Int32) -> Int32 {
        var address = sockaddr()
        var length = socklen_t(MemoryLayout<sockaddr>.size)
        return withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                accept(descriptor, socketAddress, &length)
            }
        }
    }

    private func serve(_ connection: Int32) async {
        defer { close(connection) }
        guard let request = Self.readRequest(connection) else {
            return
        }
        let response = await makeResponse(for: request)
        Self.writeResponse(response, to: connection)
    }

    private static func readRequest(_ connection: Int32) -> Request? {
        var buffer = Data()
        var headerEnd: Data.Index?
        var chunk = [UInt8](repeating: 0, count: 8192)
        let headerTerminator = Data("\r\n\r\n".utf8)

        while true {
            if headerEnd == nil {
                headerEnd = buffer.range(of: headerTerminator)?.upperBound
                if headerEnd == nil && buffer.count > 1 << 20 {
                    return nil
                }
            }
            if let currentHeaderEnd = headerEnd {
                let headerData = buffer.subdata(in: 0..<currentHeaderEnd)
                let expected = expectedBodyLength(in: headerData)
                if buffer.count >= currentHeaderEnd + expected {
                    break
                }
            }
            let received = recv(connection, &chunk, chunk.count, 0)
            if received <= 0 {
                guard let currentHeaderEnd = headerEnd else {
                    return nil
                }
                buffer = buffer.subdata(in: 0..<currentHeaderEnd)
                return parseRequest(headerData: buffer)
            }
            buffer.append(contentsOf: chunk[0..<received])
        }

        guard let currentHeaderEnd = headerEnd else {
            return nil
        }
        let headerData = buffer.subdata(in: 0..<currentHeaderEnd)
        let bodyLength = expectedBodyLength(in: headerData)
        let bodyEnd = min(buffer.count, currentHeaderEnd + bodyLength)
        let body = bodyEnd > currentHeaderEnd
            ? buffer.subdata(in: currentHeaderEnd..<bodyEnd)
            : Data()
        return parseRequest(headerData: headerData, body: body)
    }

    private static func parseRequest(headerData: Data, body: Data = Data())
        -> Request?
    {
        guard
            let headerText = String(data: headerData, encoding: .utf8),
            let firstLine = headerText.components(separatedBy: "\r\n").first
        else {
            return nil
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }
        var path = String(parts[1])
        if let queryIndex = path.firstIndex(of: "?") {
            path = String(path[path.startIndex..<queryIndex])
        }
        return Request(method: String(parts[0]).uppercased(), path: path, body: body)
    }

    private static func expectedBodyLength(in headerData: Data) -> Int {
        guard
            let headerText = String(data: headerData, encoding: .utf8)
        else {
            return 0
        }
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else {
                continue
            }
            let name = String(line[line.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.lowercased() == "content-length" else {
                continue
            }
            let value = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return dartParseInt(value) ?? 0
        }
        return 0
    }

    private static func writeResponse(_ response: Response, to connection: Int32) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(for: response.status))\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET,POST\r\n"
        head += "Access-Control-Allow-Headers: Content-Type\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n"
        if let contentType = response.contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(response.body)
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return
            }
            var sent = 0
            while sent < raw.count {
                let written = send(
                    connection,
                    base.advanced(by: sent),
                    raw.count - sent,
                    sendFlags
                )
                if written <= 0 {
                    return
                }
                sent += written
            }
        }
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200:
            return "OK"
        case 204:
            return "No Content"
        case 404:
            return "Not Found"
        default:
            return "OK"
        }
    }

    private func makeResponse(for request: Request) async -> Response {
        if request.method == "OPTIONS" {
            return Response(status: 204, contentType: nil, body: Data())
        }
        do {
            if request.method == "GET" && request.path == "/" {
                return Response(
                    status: 200,
                    contentType: "text/html; charset=utf-8",
                    body: Data(Self.indexHtml.utf8)
                )
            }
            if request.method == "POST" && request.path == "/test" {
                return try await handleTest(body: request.body)
            }
            return Response(status: 404, contentType: nil, body: Data())
        } catch {
            return Self.jsonResponse(["error": "internal error"])
        }
    }

    private func handleTest(body: Data) async throws -> Response {
        var bodyJson: [String: Any] = [:]
        if let object = try? JSONSerialization.jsonObject(with: body),
            let map = object as? [String: Any]
        {
            bodyJson = map
        }

        let siteUrl = Self.stringField(bodyJson, "siteUrl")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = Self.stringField(bodyJson, "cookie")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let templateJsonStr = Self.stringField(bodyJson, "templateJson")

        do {
            if templateJsonStr.isEmpty {
                throw RequestFailure(message: "templateJson is empty")
            }

            let template: SiteConfigTemplate
            do {
                guard
                    let templateData = templateJsonStr.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: templateData),
                    var map = object as? [String: Any]
                else {
                    throw RequestFailure(
                        message: "templateJson is not a JSON object"
                    )
                }
                map["primaryUrl"] = siteUrl
                map["id"] = "templateSite"
                template = try SiteConfigTemplate.fromJson(map)
            } catch {
                throw RequestFailure(message: "Invalid templateJson: \(error)")
            }

            let config = try template.toSiteConfig(
                selectedUrl: siteUrl,
                apiKey: nil,
                passKey: nil,
                cookie: cookie,
                userId: nil,
                isActive: false
            )

            let adapter = try SiteAdapterFactory.createAdapter(config)
            try await adapter.initialize(config)
            if let webAdapter = adapter as? NexusPHPWebAdapter {
                webAdapter.setCustomTemplate(template)
            }

            let profile = try await adapter.fetchMemberProfile(apiKey: nil)
            let categories = try await adapter.getSearchCategories()
            let search = try await adapter.searchTorrents(
                keyword: nil,
                pageNumber: 1,
                pageSize: 5,
                onlyFav: nil,
                additionalParams: nil
            )

            let top3 = search.items.prefix(3).map { item -> [String: Any] in
                [
                    "id": item.id,
                    "title": item.name,
                    "smallDescr": item.smallDescr,
                    "discount": item.discount.value,
                    "discountText": item.discount.displayText,
                    "discountEndTime": anyOrNil(item.discountEndTime.map(dartToIso8601String)),
                    "downloadUrl": anyOrNil(item.downloadUrl),
                    "seeders": item.seeders,
                    "leechers": item.leechers,
                    "sizeBytes": item.sizeBytes,
                    "cover": item.cover,
                    "createdDate": dartToIso8601String(item.createdDate),
                    "doubanRating": anyOrNil(item.doubanRating),
                    "imdbRating": anyOrNil(item.imdbRating),
                    "isTop": item.isTop,
                    "downloadStatus": String(describing: item.downloadStatus),
                    "collection": item.collection,
                    "tags": item.tags.map { String(describing: $0) },
                ]
            }

            var profileJson = profile.toJson()
            profileJson.removeValue(forKey: "uploadedBytes")
            profileJson.removeValue(forKey: "downloadedBytes")
            profileJson.removeValue(forKey: "lastAccess")
            if let rawPassKey = profileJson["passKey"], !(rawPassKey is NSNull) {
                let passKey = dartToString(rawPassKey)
                if passKey.count > 6 {
                    profileJson["passKey"] = String(passKey.suffix(6))
                }
            }

            return Self.jsonResponse([
                "profile": profileJson,
                "categories": categories.map { category -> [String: Any] in
                    ["id": category.id, "name": category.displayName]
                },
                "torrentsTop3": Array(top3),
            ])
        } catch let error as ModelsError {
            return Self.jsonResponse(["error": Self.messageText(for: error)])
        } catch {
            return Self.jsonResponse(["error": Self.messageText(for: error)])
        }
    }

    private static func messageText(for error: Error) -> String {
        if let siteError = error as? SiteException {
            return siteError.descriptionText
        }
        if let modelsError = error as? ModelsError {
            switch modelsError {
            case .formatException(let message):
                return message
            default:
                return String(describing: modelsError)
            }
        }
        return String(describing: error)
    }

    private static func stringField(_ body: [String: Any], _ key: String) -> String {
        guard let raw = body[key], !(raw is NSNull) else {
            return ""
        }
        return dartToString(raw)
    }

    private static func jsonResponse(_ object: [String: Any]) -> Response {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        else {
            return Response(status: 200, contentType: nil, body: Data())
        }
        return Response(
            status: 200,
            contentType: "application/json; charset=utf-8",
            body: data
        )
    }

    private static let indexHtml = """
<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>PTMate Web 调试</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 16px; }
    label { display:block; margin-top:12px; }
    input, textarea { width:100%; padding:8px; margin-top:4px; }
    button { margin-top:16px; padding:8px 12px; }
    pre { background:#f6f8fa; padding:12px; overflow:auto; }
  </style>
  </head>
<body>
  <h2>PTMate Web 调试</h2>
  <label>站点地址
    <input id="siteUrl" placeholder="https://example.com" />
  </label>
  <label>Cookie
    <input id="cookie" placeholder="uid=...; pass=..." />
  </label>
  <label>详细配置（参考 assets/sites/ 下面的 <a href="https://github.com/JustLookAtNow/pt_mate/tree/master/assets/sites">json 文件</a>）
    <p>另有配置说明一份，参考 <a href="https://github.com/JustLookAtNow/pt_mate/blob/master/SITE_CONFIGURATION_GUIDE.md">配置说明</a></p>
    <textarea id="templateJson" rows="12" placeholder="{
  ...
}"></textarea>
  </label>
  <button id="testBtn">测试</button>
  <h3>返回结果</h3>
  <pre id="out"></pre>
  <script>
    const el = (id) => document.getElementById(id);
    el('testBtn').onclick = async () => {
      el('out').textContent = '测试中...';
      const payload = {
        siteUrl: el('siteUrl').value.trim(),
        cookie: el('cookie').value.trim(),
        templateJson: el('templateJson').value.trim(),
      };
      try {
        const res = await fetch('/test', {
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body: JSON.stringify(payload)
        });
        const json = await res.json();
        el('out').textContent = JSON.stringify(json, null, 2);
      } catch (e) {
        el('out').textContent = '请求失败: ' + e;
      }
    };
  </script>
</body>
</html>
"""
}