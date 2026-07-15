import Foundation

/// Speaks Swiggy's MCP over HTTPS. Given a valid access token in Keychain,
/// asks the server for active Food + Instamart orders and returns them as
/// unified `Order` values ready to drop into `OrdersState`.
///
/// Protocol quirks (learned the hard way — see the `gotcha-swiggy-mcp-protocol` memory):
///   • Food and Instamart live on DIFFERENT endpoints:
///       Food      → https://mcp.swiggy.com/food
///       Instamart → https://mcp.swiggy.com/im   (not /instamart!)
///   • `Accept` header MUST include BOTH `application/json` and `text/event-stream`
///   • Response may be raw JSON or SSE-framed — we handle both
///   • Real data lives in `result.structuredContent`, EXCEPT for `track_food_order`
///     which returns empty structuredContent — use `get_food_orders` instead.
///   • `get_food_orders` requires `addressId`. Any addressId works with
///     `activeOnly: true` — we fetch one via `get_addresses` and cache it.
///   • For each active Food order we ALSO call `get_food_delivery_status` to
///     get a live ETA, terminal flags (delivered/cancelled), and Swiggy's
///     suggested `pollIntervalSec`. Food ETA lives in a separate tool, not
///     in `get_food_orders`.
@MainActor
final class MCPClient {

    // MARK: - Configuration

    private let foodEndpoint = URL(string: "https://mcp.swiggy.com/food")!
    private let instamartEndpoint = URL(string: "https://mcp.swiggy.com/im")!

    /// JSON-RPC request ids must be unique per session. Simple monotonic counter.
    private var nextRequestId = 1

    /// Some MCP servers return a session id on the first response that must be
    /// echoed on subsequent requests. Cached here; nil until the server gives us one.
    private var sessionId: String?

    /// Any valid Swiggy addressId, cached for the app's lifetime.
    /// `get_food_orders` demands one via schema; the value doesn't affect which
    /// active orders come back, so we fetch once and reuse.
    private var cachedAddressId: String?

    // MARK: - Public API

    /// A single poll's output: the current orders + Swiggy's suggested next
    /// poll interval (only present when Food status was fetched, since that's
    /// where `pollIntervalSec` lives). Instamart doesn't offer one.
    struct FetchResult {
        let orders: [Order]
        /// Seconds until the next poll, per Swiggy's `pollIntervalSec`.
        /// `nil` means we didn't get a hint — caller should use its default.
        let suggestedPollInterval: TimeInterval?
    }

    /// Fetch every active order across Food + Instamart, in parallel.
    /// If one platform errors, the whole call throws — the poller decides
    /// whether that's a soft or hard failure.
    func fetchActiveOrders() async throws -> FetchResult {
        async let food = fetchFoodOrders()
        async let insta = fetchInstamartOrders()
        let (foodResult, instaOrders) = try await (food, insta)
        return FetchResult(
            orders: foodResult.orders + instaOrders,
            suggestedPollInterval: foodResult.minPollInterval
        )
    }

    // MARK: - Per-platform fetches

    private struct FoodFetchOutcome {
        let orders: [Order]
        /// The lowest `pollIntervalSec` reported across all active Food orders.
        /// Swiggy tightens the interval as delivery approaches; the caller
        /// should respect the fastest one so no order gets stale.
        let minPollInterval: TimeInterval?
    }

    /// Two-hop Food fetch: list active orders, then enrich each with live
    /// delivery status (ETA + terminal flags + poll interval).
    private func fetchFoodOrders() async throws -> FoodFetchOutcome {
        let addressId = try await addressIdForFoodQueries()
        let listResult: FoodOrdersResult = try await callTool(
            endpoint: foodEndpoint,
            name: "get_food_orders",
            arguments: [
                "addressId": addressId,
                "activeOnly": true
            ]
        )
        let rawOrders = listResult.orders ?? []

        // For each active order, try to fetch live delivery status. Individual
        // failures are tolerated: the order still appears, just without ETA
        // (nil). We poll serially — typically 1–2 active orders, not worth
        // TaskGroup complexity.
        var orders: [Order] = []
        var minInterval: TimeInterval?
        for raw in rawOrders {
            let status: FoodDeliveryStatus? = try? await fetchFoodDeliveryStatus(orderId: raw.orderId)

            // Terminal flags win over `isActiveOrder` from the list —
            // `get_food_delivery_status` is more current.
            if status?.delivered == true || status?.cancelled == true {
                continue
            }
            if let order = Order(food: raw, status: status) {
                orders.append(order)
            }
            if let sec = status?.pollIntervalSec {
                let asInterval = TimeInterval(sec)
                minInterval = min(minInterval ?? asInterval, asInterval)
            }
        }
        return FoodFetchOutcome(orders: orders, minPollInterval: minInterval)
    }

    private func fetchInstamartOrders() async throws -> [Order] {
        let result: InstamartOrdersResult = try await callTool(
            endpoint: instamartEndpoint,
            name: "get_orders",
            arguments: ["activeOnly": true]
        )
        return result.orders.compactMap(Order.init(instamart:))
    }

    /// Live-tracking side-call for a single Food order. Returns the ETA text,
    /// absolute deliver-by timestamp (Swiggy's clock in ms), terminal flags,
    /// and a suggested poll cadence.
    private func fetchFoodDeliveryStatus(orderId: String) async throws -> FoodDeliveryStatus {
        return try await callTool(
            endpoint: foodEndpoint,
            name: "get_food_delivery_status",
            arguments: ["orderId": orderId]
        )
    }

    /// Return an addressId suitable for `get_food_orders`, fetching + caching
    /// on first call. The specific id doesn't matter for our use case
    /// (activeOnly returns the same orders regardless), so we just pick the
    /// first address the server lists.
    private func addressIdForFoodQueries() async throws -> String {
        if let cached = cachedAddressId { return cached }
        let result: AddressesResult = try await callTool(
            endpoint: foodEndpoint,
            name: "get_addresses",
            arguments: [:]
        )
        guard let first = result.addresses.first else {
            throw MCPError.noAddresses
        }
        cachedAddressId = first.id
        return first.id
    }

    // MARK: - Generic tool call
    //
    // The single funnel every tool call goes through. Handles auth, headers,
    // SSE unwrapping, JSON-RPC envelope, and structuredContent extraction.

    private func callTool<Result: Decodable>(
        endpoint: URL,
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

        var request = URLRequest(url: endpoint)
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
    /// `get_addresses` returned zero addresses — can't build a Food query.
    case noAddresses

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:  return "Not signed in to Swiggy."
        case .unauthorized:      return "Swiggy sign-in expired. Please sign in again."
        case .httpError(let s, let b): return "Swiggy returned \(s): \(b)"
        case .invalidResponse:   return "Unexpected response from Swiggy."
        case .missingStructuredContent: return "Swiggy returned data in an unexpected shape."
        case .toolError(let m):  return "Swiggy: \(m)"
        case .noAddresses:       return "No saved addresses on your Swiggy account."
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
// Shapes are based on the captured MCP responses in `data/*.jsonl` and the
// live-order probe done on 2026-07-15. If the server's response ever changes,
// refresh those captures first — don't guess.

private struct AddressesResult: Decodable {
    let addresses: [AddressRaw]
}

private struct AddressRaw: Decodable {
    let id: String
}

private struct FoodOrdersResult: Decodable {
    let orders: [FoodOrderRaw]?
}

private struct FoodOrderRaw: Decodable {
    let orderId: String
    let restaurantName: String
    let restaurantAreaName: String?
    let orderStatus: String       // "processing" | "Delivered" (coarse — see project memory)
    let orderedItems: String      // e.g. "Paneer Lemon Dry (1),Cream of Broccoli Soup (1)"
    let isActiveOrder: Bool
}

/// Response from `get_food_delivery_status`. `deliveryBy` and `serverNow` are
/// Swiggy's clock in ms epoch — the remaining time is `deliveryBy - serverNow`.
/// Using this pair (instead of the local clock) means we're immune to device
/// clock drift.
private struct FoodDeliveryStatus: Decodable {
    let orderId: String
    let deliveryBy: Int64
    let serverNow: Int64
    let etaText: String?      // Human copy, e.g. "2 mins". May be nil close to arrival.
    let cancelled: Bool
    let delivered: Bool
    let pollIntervalSec: Int?
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

    /// Build an Order from a raw Food response row plus (optionally) the live
    /// delivery status. Returns nil if the order isn't active.
    ///
    /// - When `status` is present, uses it to compute a real ETA in minutes
    ///   and to override `orderStatus` with a finer label near delivery.
    /// - When `status` is nil (the side-call failed), still shows the order —
    ///   just with `eta = nil`.
    init?(food raw: FoodOrderRaw, status: FoodDeliveryStatus?) {
        guard raw.isActiveOrder else { return nil }

        // Multi-item context.
        // "Paneer Lemon Dry (1),Cream of Broccoli Soup (1)"
        //   → "Paneer Lemon Dry, Cream of Broccoli Soup"
        // Trailing " (N)" quantity and " [Size]" variant are stripped per item.
        let itemNames: [String] = raw.orderedItems
            .split(separator: ",")
            .map { chunk in
                String(chunk)
                    .replacingOccurrences(of: #" \([0-9]+\)$"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #" \[[^\]]+\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        let itemsLabel = itemNames.joined(separator: ", ")

        // Status → progress. Food's `orderStatus` is coarse
        // ("processing" | "Delivered"), so we blend in the delivery status's
        // ETA to differentiate "in progress, far out" from "arriving soon".
        let progress: ProgressStage
        let statusLabel: String
        let remainingMinutes: Int? = status.map {
            let deltaMs = max(0, $0.deliveryBy - $0.serverNow)
            return Int((Double(deltaMs) / 60_000.0).rounded())
        }

        switch raw.orderStatus.lowercased() {
        case "delivered":
            progress = .delivered
            statusLabel = "Delivered"
        case "processing":
            if let mins = remainingMinutes, mins <= 3 {
                progress = .nearby
                statusLabel = "Arriving soon"
            } else if let mins = remainingMinutes, mins <= 10 {
                progress = .inTransit
                statusLabel = "On the way"
            } else {
                progress = .preparing
                statusLabel = "Order in progress"
            }
        default:
            progress = .placed
            statusLabel = raw.orderStatus.capitalized
        }

        self.init(
            id: raw.orderId,
            platform: .food,
            context: "\(raw.restaurantName) • \(itemsLabel)",
            status: statusLabel,
            eta: remainingMinutes,
            progress: progress
        )
    }

    /// Build an Order from a raw Instamart response row. Returns nil if the
    /// order isn't currently active.
    init?(instamart raw: InstamartOrderRaw) {
        guard raw.isActive else { return nil }

        let store = raw.storeName ?? "Instamart"
        // Show all items where available (matches Food behaviour above).
        let itemNames = (raw.items ?? []).map { $0.name }
        let itemsLabel = itemNames.joined(separator: ", ")
        let context = itemsLabel.isEmpty ? store : "\(store) • \(itemsLabel)"

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
