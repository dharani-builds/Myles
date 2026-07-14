import Foundation

/// Speaks Swiggy's MCP over HTTPS. Given a valid access token in Keychain,
/// asks the server for active Food + Instamart orders and returns them as
/// unified `Order` values ready to drop into `OrdersState`.
///
/// Protocol quirks (learned the hard way during Phase 0 — see the
/// `gotcha-swiggy-mcp-protocol` memory):
///   • `Accept` header MUST include BOTH `application/json` and `text/event-stream`
///   • Response may be raw JSON or SSE-framed — we handle both
///   • Real data lives in `result.structuredContent`, not `content[].text`
@MainActor
final class MCPClient {

    // MARK: - Configuration

    private let baseURL = URL(string: "https://mcp.swiggy.com/mcp")!

    /// JSON-RPC request ids must be unique per session. Simple monotonic counter.
    private var nextRequestId = 1

    /// Some MCP servers return a session id on the first response that must be
    /// echoed on subsequent requests. Cached here; nil until the server gives us one.
    private var sessionId: String?

    // MARK: - Public API

    /// Fetch every active order across Food + Instamart, in parallel.
    /// If one platform errors, the whole call throws — the poller decides
    /// whether that's a soft or hard failure.
    func fetchActiveOrders() async throws -> [Order] {
        async let food = fetchFoodOrders()
        async let instamart = fetchInstamartOrders()
        return try await food + instamart
    }

    // MARK: - Per-platform fetches

    private func fetchFoodOrders() async throws -> [Order] {
        let result: FoodOrdersResult = try await callTool(
            name: "track_food_order",
            arguments: [:]
        )
        return (result.orders ?? []).compactMap(Order.init(food:))
    }

    private func fetchInstamartOrders() async throws -> [Order] {
        let result: InstamartOrdersResult = try await callTool(
            name: "get_orders",
            arguments: [:]
        )
        return result.orders.compactMap(Order.init(instamart:))
    }

    // MARK: - Generic tool call
    //
    // The single funnel every tool call goes through. Handles auth, headers,
    // SSE unwrapping, JSON-RPC envelope, and structuredContent extraction.

    private func callTool<Result: Decodable>(
        name: String,
        arguments: [String: Any]
    ) async throws -> Result {
        guard let token = KeychainStore.get(.swiggyAccessToken) else {
            throw MCPError.notAuthenticated
        }

        let requestId = nextRequestId
        nextRequestId += 1

        // JSON-RPC 2.0 envelope
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments
            ],
            "id": requestId
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // BOTH required — see gotcha memory
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }

        // Cache any server-assigned session id for future calls
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionId = sid
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw MCPError.unauthorized }
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw MCPError.httpError(status: http.statusCode, body: bodyText)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let jsonData = try extractJSON(from: data, contentType: contentType)

        let envelope = try JSONDecoder().decode(JSONRPCResponse<ToolCallResult<Result>>.self, from: jsonData)

        if let error = envelope.error {
            throw MCPError.toolError(error.message)
        }
        guard let structured = envelope.result?.structuredContent else {
            throw MCPError.missingStructuredContent
        }
        return structured
    }

    /// If the response came back as SSE (`text/event-stream`), pull the JSON
    /// out of the last `data:` line. Otherwise return the body untouched.
    private func extractJSON(from data: Data, contentType: String) throws -> Data {
        guard contentType.lowercased().contains("text/event-stream") else {
            return data
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPError.invalidResponse
        }
        // SSE frames look like:
        //   event: message
        //   data: {"jsonrpc":"2.0", ...}
        //
        //   (blank line separates frames)
        let dataLines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.hasPrefix("data: ") }
            .map { String($0.dropFirst("data: ".count)) }
        // The last data line has the full JSON payload (earlier frames, if any,
        // are usually protocol-level pings we can ignore).
        guard let jsonString = dataLines.last,
              let d = jsonString.data(using: .utf8) else {
            throw MCPError.invalidResponse
        }
        return d
    }
}

// MARK: - Errors

enum MCPError: LocalizedError {
    /// No access token in Keychain — user never signed in, or was signed out.
    case notAuthenticated
    /// Server returned 401 — token expired or was revoked. Caller should trigger re-auth.
    case unauthorized
    case httpError(status: Int, body: String)
    case invalidResponse
    /// The response's `result.structuredContent` was missing.
    case missingStructuredContent
    /// The tool ran, but returned a JSON-RPC error object.
    case toolError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return "Not signed in to Swiggy."
        case .unauthorized:      return "Swiggy sign-in expired. Please sign in again."
        case .httpError(let s, let b): return "Swiggy returned \(s): \(b)"
        case .invalidResponse:   return "Unexpected response from Swiggy."
        case .missingStructuredContent: return "Swiggy returned data in an unexpected shape."
        case .toolError(let m):  return "Swiggy: \(m)"
        }
    }
}

// MARK: - JSON-RPC + MCP envelopes

private struct JSONRPCResponse<Payload: Decodable>: Decodable {
    let result: Payload?
    let error: JSONRPCError?
}

private struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

/// Shape of `result` for a `tools/call` response. We ignore `content` — it's
/// prose for LLMs. All the JSON we care about is in `structuredContent`.
private struct ToolCallResult<Structured: Decodable>: Decodable {
    let structuredContent: Structured?
}

// MARK: - Raw response shapes
//
// Shapes are based on the captured MCP responses in `data/*.jsonl`. If the
// server's response ever changes, refresh those captures first — don't guess.

private struct FoodOrdersResult: Decodable {
    let orders: [FoodOrderRaw]?
}

private struct FoodOrderRaw: Decodable {
    let orderId: String
    let restaurantName: String
    let restaurantAreaName: String?
    let orderStatus: String       // "processing" | "Delivered" (coarse — see project memory)
    let orderedItems: String      // e.g. "Chicken Tikka Sandwich [Single] (1), Coke (1)"
    let isActiveOrder: Bool
}

private struct InstamartOrdersResult: Decodable {
    let orders: [InstamartOrderRaw]
}

private struct InstamartOrderRaw: Decodable {
    let orderId: String
    let currentStatus: String                    // e.g. "Order picked up"
    let statusMessage: String?                   // e.g. "DAVAL SAB has picked up your order"
    let estimatedDeliveryTime: String?           // e.g. "13 mins"
    let isActive: Bool
    let storeName: String?
    let items: [InstamartItem]?
}

private struct InstamartItem: Decodable {
    let name: String
}

// MARK: - Raw → Order mappers
//
// These sit here (private extension) because they need access to the raw types
// above but produce our public `Order` model. If mapping gets more complex,
// pull it into a separate `OrderMapping.swift`.

private extension Order {

    /// Build an Order from a raw Food response row. Returns nil if the row
    /// isn't an active order (already delivered, cancelled, etc.).
    init?(food raw: FoodOrderRaw) {
        guard raw.isActiveOrder else { return nil }

        // "Chicken Tikka Sandwich [Single] (1), Coke (1)"
        //  → "Chicken Tikka Sandwich"  (first item, size + qty stripped)
        let firstChunk = raw.orderedItems
            .split(separator: ",").first
            .map(String.init) ?? raw.orderedItems
        let itemName = firstChunk
            .replacingOccurrences(of: #" \([0-9]+\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" \[[^\]]+\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // Food's status is a coarse 2-value enum. Best we can do until Swiggy
        // exposes finer states. See project memory + `data/food-*.jsonl`.
        let progress: ProgressStage
        let statusLabel: String
        switch raw.orderStatus.lowercased() {
        case "delivered":
            progress = .delivered
            statusLabel = "Delivered"
        case "processing":
            progress = .preparing
            statusLabel = "Order in progress"
        default:
            progress = .placed
            statusLabel = raw.orderStatus.capitalized
        }

        self.init(
            id: raw.orderId,
            platform: .food,
            context: "\(raw.restaurantName) • \(itemName)",
            status: statusLabel,
            eta: nil,   // Food doesn't expose an ETA field via MCP
            progress: progress
        )
    }

    /// Build an Order from a raw Instamart response row. Returns nil if the
    /// order isn't currently active.
    init?(instamart raw: InstamartOrderRaw) {
        guard raw.isActive else { return nil }

        let store = raw.storeName ?? "Instamart"
        let firstItem = raw.items?.first?.name ?? ""
        let context = firstItem.isEmpty ? store : "\(store) • \(firstItem)"

        // "13 mins" → 13. Anything unparseable → nil.
        let eta: Int? = raw.estimatedDeliveryTime
            .flatMap { $0.split(separator: " ").first }
            .flatMap { Int($0) }

        // Progress inferred from keywords in `currentStatus`. Order matters:
        // "delivered" wins over "picked up" (a delivered order has been both).
        let cs = raw.currentStatus.lowercased()
        let progress: ProgressStage
        if cs.contains("delivered") {
            progress = .delivered
        } else if cs.contains("nearby") || cs.contains("minutes away") || cs.contains("arriving") {
            progress = .nearby
        } else if cs.contains("picked up") || cs.contains("on the way") || cs.contains("out for delivery") {
            progress = .inTransit
        } else if cs.contains("packed") {
            progress = .packed
        } else if cs.contains("confirmed") || cs.contains("received") {
            progress = .placed
        } else {
            progress = .placed
        }

        self.init(
            id: raw.orderId,
            platform: .instamart,
            context: context,
            status: raw.currentStatus,
            eta: eta,
            progress: progress
        )
    }
}
