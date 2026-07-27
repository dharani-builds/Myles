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

    /// A single poll's output.
    struct FetchResult {
        let orders: [Order]
        /// Seconds until the next poll — the tightest interval Swiggy suggested
        /// across all active orders (Food's `pollIntervalSec`, Instamart's
        /// `pollingIntervalSeconds`). `nil` means no hint; caller uses its default.
        let suggestedPollInterval: TimeInterval?
        /// Platforms whose fetch threw this cycle. Critical for the caller:
        /// a platform that failed is NOT the same as a platform with no orders,
        /// and conflating the two makes a delivered-order celebration fire on
        /// a transient network blip. `OrdersState` uses this to carry forward
        /// last-known orders and to suppress the celebration.
        let failedPlatforms: Set<OrderPlatform>
        /// Order IDs that Swiggy explicitly told us are complete this cycle
        /// (Instamart `pollingIntervalSeconds == -1`, Food `delivered == true`).
        /// Positive evidence of delivery, as opposed to an order merely
        /// disappearing from the active list.
        let deliveredOrderIds: Set<String>
    }

    /// Fetch every active order across Food + Instamart, in parallel, with
    /// **per-platform soft-fail**:
    ///   • If either platform returns `unauthorized`, propagate immediately —
    ///     token is dead, no point continuing to show partial data.
    ///   • If exactly one platform errors (any other reason), return what the
    ///     other returned. Partial data > no data > silent failure.
    ///   • If both fail, throw the first non-auth error. Poller escalates.
    func fetchActiveOrders() async throws -> FetchResult {
        async let food = fetchFoodOrders()
        async let insta = fetchInstamartOrders()

        var foodOutcome: FoodFetchOutcome?
        var instaOutcome: InstamartFetchOutcome?
        var errors: [Error] = []
        var failed: Set<OrderPlatform> = []

        do {
            foodOutcome = try await food
        } catch {
            errors.append(error)
            failed.insert(.food)
        }
        do {
            instaOutcome = try await insta
        } catch {
            errors.append(error)
            failed.insert(.instamart)
        }

        // Any 401 anywhere means the shared token is dead — force sign-out.
        for err in errors {
            if let mcpErr = err as? MCPError, case .unauthorized = mcpErr {
                throw MCPError.unauthorized
            }
        }

        // Both platforms failed (non-auth) → propagate the first error so the
        // poller can escalate to `.error` after its own consecutive-failure threshold.
        if foodOutcome == nil && instaOutcome == nil, let first = errors.first {
            throw first
        }

        // At least one platform succeeded — return partial data, but tell the
        // caller which platform (if any) failed so it doesn't read the gap as
        // "those orders are gone".
        let intervals = [foodOutcome?.minPollInterval, instaOutcome?.minPollInterval].compactMap { $0 }
        return FetchResult(
            orders: (foodOutcome?.orders ?? []) + (instaOutcome?.orders ?? []),
            suggestedPollInterval: intervals.min(),
            failedPlatforms: failed,
            deliveredOrderIds: (foodOutcome?.deliveredIds ?? []).union(instaOutcome?.deliveredIds ?? [])
        )
    }

    // MARK: - Per-platform fetches

    private struct FoodFetchOutcome {
        let orders: [Order]
        /// The lowest `pollIntervalSec` reported across all active Food orders.
        /// Swiggy tightens the interval as delivery approaches; the caller
        /// should respect the fastest one so no order gets stale.
        let minPollInterval: TimeInterval?
        /// Orders Swiggy flagged `delivered` this cycle.
        let deliveredIds: Set<String>
    }

    private struct InstamartFetchOutcome {
        let orders: [Order]
        /// Lowest `pollingIntervalSeconds` across active Instamart orders.
        let minPollInterval: TimeInterval?
        /// Orders where `track_order` returned `pollingIntervalSeconds == -1`,
        /// Swiggy's "this order is finished, stop polling" signal.
        let deliveredIds: Set<String>
    }

    /// A permissive decodable used ONLY for capture-only side-calls where we
    /// don't consume the response — we just want it to land in the JSONL log.
    /// If the tool returns structuredContent, this happily decodes anything;
    /// if it doesn't (see `track_food_order`), callTool throws
    /// `missingStructuredContent` AFTER the capture has already been written.
    private struct CaptureOnlyResult: Decodable {}

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

        // Capture-only: same tool with activeOnly:false gives us the full
        // history including recently-delivered orders. Those responses may
        // carry fields (final orderDeliveryStatus, terminal timestamps, etc.)
        // that the active-only view drops. Result discarded — capture lands
        // in the JSONL via callTool's built-in append.
        let _: CaptureOnlyResult? = try? await callTool(
            endpoint: foodEndpoint,
            name: "get_food_orders",
            arguments: [
                "addressId": addressId,
                "activeOnly": false
            ]
        )

        // For each active order, try to fetch live delivery status. Individual
        // failures are tolerated: the order still appears, just without ETA
        // (nil). We poll serially — typically 1–2 active orders, not worth
        // TaskGroup complexity.
        var orders: [Order] = []
        var minInterval: TimeInterval?
        var deliveredIds: Set<String> = []
        for raw in rawOrders {
            let status: FoodDeliveryStatus? = try? await fetchFoodDeliveryStatus(orderId: raw.orderId)

            // track_food_order — the conversational status text ("Order
            // Received!", "Partner is on the way", etc.) that we use as
            // the status label. Content channel, not structuredContent.
            let trackText: String? = try? await callToolForContentText(
                endpoint: foodEndpoint,
                name: "track_food_order",
                arguments: ["orderId": raw.orderId]
            )

            // Capture-only — data we're logging but not consuming yet.
            let _: CaptureOnlyResult? = try? await callTool(
                endpoint: foodEndpoint,
                name: "get_food_order_details",
                arguments: ["orderId": raw.orderId]
            )

            // Terminal flags win over `isActiveOrder` from the list —
            // `get_food_delivery_status` is more current. Only `delivered`
            // counts as a celebration-worthy finish; a cancelled order is
            // dropped silently.
            if status?.delivered == true {
                deliveredIds.insert(raw.orderId)
                continue
            }
            if status?.cancelled == true {
                continue
            }
            if let order = Order(food: raw, status: status, trackText: trackText) {
                orders.append(order)
            }
            if let sec = status?.pollIntervalSec {
                let asInterval = TimeInterval(sec)
                minInterval = min(minInterval ?? asInterval, asInterval)
            }
        }
        return FoodFetchOutcome(
            orders: orders,
            minPollInterval: minInterval,
            deliveredIds: deliveredIds
        )
    }

    /// Two-hop Instamart fetch, mirroring Food.
    ///
    /// `get_orders` gives the list plus the ETA string, but its status fields
    /// LAG — observed live on 2026-07-27 reporting "Order picked up" while the
    /// partner had already reached the door. `track_order` is Swiggy's actual
    /// tracking endpoint ("PRIMARY TOOL for order tracking" per its own schema)
    /// and carries the current two-line copy plus a poll cadence.
    ///
    /// `track_order` marks lat/lng required but keys off `orderId` — verified
    /// that 0,0 returns the correct order — so we don't need real coordinates,
    /// which `get_orders` doesn't expose anyway.
    private func fetchInstamartOrders() async throws -> InstamartFetchOutcome {
        let result: InstamartOrdersResult = try await callTool(
            endpoint: instamartEndpoint,
            name: "get_orders",
            arguments: ["activeOnly": true]
        )

        var orders: [Order] = []
        var minInterval: TimeInterval?
        var deliveredIds: Set<String> = []

        for raw in result.orders where raw.isActive {
            let tracking: InstamartTrackingRaw? = try? await callTool(
                endpoint: instamartEndpoint,
                name: "track_order",
                arguments: ["orderId": raw.orderId, "lat": 0, "lng": 0]
            )

            // pollingIntervalSeconds == -1 is Swiggy saying "finished, stop
            // polling". That's an explicit terminal signal — far better than
            // inferring delivery from an order dropping out of the list.
            if let secs = tracking?.pollingIntervalSeconds, secs < 0 {
                deliveredIds.insert(raw.orderId)
                continue
            }
            if let secs = tracking?.pollingIntervalSeconds, secs > 0 {
                let asInterval = TimeInterval(secs)
                minInterval = min(minInterval ?? asInterval, asInterval)
            }

            if let order = Order(instamart: raw, tracking: tracking) {
                orders.append(order)
            }
        }

        return InstamartFetchOutcome(
            orders: orders,
            minPollInterval: minInterval,
            deliveredIds: deliveredIds
        )
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

        // Forensic capture — every raw response goes to disk before decoding.
        // See MCPCaptureLog for path + shape. Cheap append; failures swallowed.
        MCPCaptureLog.shared.append(
            tool: name,
            endpoint: endpoint,
            arguments: arguments,
            responseJSON: jsonData
        )

        let envelope = try JSONDecoder().decode(JSONRPCResponse<ToolCallResult<Result>>.self, from: jsonData)

        if let error = envelope.error {
            throw MCPError.toolError(error.message)
        }
        guard let structured = envelope.result?.structuredContent else {
            throw MCPError.missingStructuredContent
        }
        return structured
    }

    /// Companion to `callTool` for tools whose useful data lives in the
    /// prose `content[]` channel instead of `structuredContent`. Right now
    /// this is only `track_food_order` — its structuredContent comes back
    /// empty, but `content[0].text` carries the actual conversational status
    /// ("Partner is on the way", etc.).
    ///
    /// Same request/response plumbing as `callTool`, same JSONL capture,
    /// just decodes a different field. Returns nil if no content text is
    /// present (which is normal — the caller should fall back).
    private func callToolForContentText(
        endpoint: URL,
        name: String,
        arguments: [String: Any]
    ) async throws -> String? {
        guard let token = KeychainStore.get(.swiggyAccessToken) else {
            throw MCPError.notAuthenticated
        }

        let requestId = nextRequestId
        nextRequestId += 1

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
            "id": requestId
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }
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

        MCPCaptureLog.shared.append(
            tool: name,
            endpoint: endpoint,
            arguments: arguments,
            responseJSON: jsonData
        )

        let envelope = try JSONDecoder().decode(JSONRPCResponse<ToolCallResult<CaptureOnlyResult>>.self, from: jsonData)
        if let error = envelope.error {
            throw MCPError.toolError(error.message)
        }
        return envelope.result?.content?.first?.text
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

/// Shape of `result` for a `tools/call` response.
///
/// `structuredContent` is the clean JSON we decode into typed models for the
/// UI. `content` is the prose channel — Swiggy uses this for LLM-consumable
/// text and, for `track_food_order`, this is currently the ONLY place any
/// data lands (structuredContent comes back empty). We keep `content` around
/// so the JSONL capture layer sees it too, and so anything conversational
/// that lives here isn't silently lost.
private struct ToolCallResult<Structured: Decodable>: Decodable {
    let structuredContent: Structured?
    let content: [ContentBlock]?
}

private struct ContentBlock: Decodable {
    let type: String?
    let text: String?
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
    /// Second status field observed in captured responses. For delivered
    /// orders it's "delivered"; unknown enum values during active delivery.
    /// Kept optional + decoded but currently unused — the capture layer
    /// preserves it so a live order will expose its real values in the JSONL.
    let orderDeliveryStatus: String?
    let orderedItems: String      // e.g. "Paneer Lemon Dry (1),Cream of Broccoli Soup (1)"
    let orderTotal: String?       // e.g. "₹176". For future display.
    let orderedTime: String?      // e.g. "July 23, 8:39 PM"
    let orderType: String?        // e.g. "regular"
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

/// Response from Instamart's `track_order`. This is the live view — the
/// status here leads `get_orders` by a stage or more.
///
/// Observed live 2026-07-27:
///   mid-delivery → statusMessage "Arrived at location"
///                  subStatusMessage "SIDDANNA GOWDA has reached your location"
///                  pollingIntervalSeconds 30
///   delivered    → statusMessage "Order Delivered"
///                  subStatusMessage absent
///                  pollingIntervalSeconds -1
private struct InstamartTrackingRaw: Decodable {
    struct StatusBlock: Decodable {
        /// Headline status, e.g. "Arrived at location", "Order Delivered".
        let statusMessage: String?
        /// Partner-level detail, e.g. "SIDDANNA GOWDA has reached your location".
        /// Absent in states with no partner attached yet, and once delivered.
        let subStatusMessage: String?
    }
    let status: StatusBlock?
    /// Swiggy's suggested cadence. `-1` means the order is finished.
    let pollingIntervalSeconds: Int?
}

// MARK: - Raw → Order mappers
//
// These sit here (private extension) because they need access to the raw types
// above but produce our public `Order` model. If mapping gets more complex,
// pull it into a separate `OrderMapping.swift`.

private extension Order {

    /// Build an Order from a raw Food response row plus (optionally) the live
    /// delivery status and the track_food_order prose text. Returns nil if
    /// the order isn't active.
    ///
    /// - `status` (from `get_food_delivery_status`): live ETA + terminal flags.
    /// - `trackText` (from `track_food_order.content[0].text`): Swiggy's own
    ///   conversational status phrase, e.g.
    ///     `Order 24394...: Partner is on the way (Frozen Bottle...) - ETA: 14 mins`
    ///   We parse the middle phrase and use it as the status label when
    ///   available — that's Swiggy's real user-facing copy. Otherwise we
    ///   fall back to the ETA-bucketed labels we invent locally.
    init?(food raw: FoodOrderRaw, status: FoodDeliveryStatus?, trackText: String? = nil) {
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

        // Food's `orderStatus` is coarse ("processing" | "Delivered"), so
        // both the status label and the bar are derived from ETA.
        //
        // Status label — still stepwise (three milestone phrases):
        //   ETA > 10 min  → "Order in progress"
        //   3 < ETA ≤ 10  → "On the way"
        //   ETA ≤ 3       → "Arriving soon"
        //
        // Progress bar — CONTINUOUS. Uses a linear map from remaining ETA
        // to a fraction, clamped [0.20 … 0.97]. So the bar physically
        // slides each poll instead of jumping between three fixed steps.
        // Formula: as ETA counts down 45 → 0, bar fills 20% → 97%.
        // The 0.97 ceiling leaves room to show a distinct 100% at delivery.
        // 45 minutes as `maxETA` matches Swiggy's typical order upper bound;
        // longer orders clamp to the 20% floor until they drop below 45min.
        let statusLabel: String
        let remainingMinutes: Int? = status.map {
            let deltaMs = max(0, $0.deliveryBy - $0.serverNow)
            return Int((Double(deltaMs) / 60_000.0).rounded())
        }

        // Swiggy's own conversational phrase (if we got it) beats any label
        // we might invent — it's the same copy shown in the iOS Live Activity.
        let swiggyPhrase = Order.parseTrackOrderStatusPhrase(trackText)

        // Fallback labels — used only when `track_food_order`'s prose is
        // missing or unparseable. Deliberately mirror Swiggy's own phrasing
        // ("Preparing your order", "Out for delivery") so the user can't tell
        // whether the fallback fired or not. Kept in sync with the iOS
        // Live Activity copy.
        let progressFraction: Double
        switch raw.orderStatus.lowercased() {
        case "delivered":
            progressFraction = 1.0
            statusLabel = swiggyPhrase ?? "Order delivered!"
        case "processing":
            progressFraction = Self.foodProgressFromETA(remainingMinutes)
            if let phrase = swiggyPhrase {
                statusLabel = phrase
            } else if let mins = remainingMinutes, mins <= 3 {
                statusLabel = "Arriving soon"
            } else if let mins = remainingMinutes, mins <= 10 {
                statusLabel = "Out for delivery"
            } else {
                statusLabel = "Preparing your order"
            }
        default:
            // "just placed" state before Swiggy flips to processing.
            progressFraction = 0.10
            statusLabel = swiggyPhrase ?? "Order received"
        }

        self.init(
            id: raw.orderId,
            platform: .food,
            context: "\(raw.restaurantName) • \(itemsLabel)",
            status: statusLabel,
            eta: remainingMinutes,
            progress: progressFraction
        )
    }

    /// Continuous ETA-to-progress mapping. See init?(food:status:) for the
    /// design notes. Extracted so it's easy to swap the curve later without
    /// hunting through the switch.
    private static func foodProgressFromETA(_ mins: Int?) -> Double {
        guard let mins = mins, mins >= 0 else { return 0.20 }
        let maxETA: Double = 45
        let raw = 1.0 - min(Double(mins), maxETA) / maxETA
        return min(0.97, max(0.20, raw))
    }

    /// Extract Swiggy's conversational status phrase from the
    /// `track_food_order` prose text. Expected format (observed in live
    /// capture on 2026-07-25):
    ///
    ///     "Order 243...: Partner is on the way (Frozen Bottle...) - ETA: 14 mins"
    ///
    /// The phrase between `: ` and the trailing ` (` is what we want.
    /// Returns nil if the input is nil, empty, or doesn't match — caller
    /// falls back to invented labels in that case (see init?(food:...)).
    ///
    /// Deliberately permissive: if Swiggy changes the format around
    /// delivery or edge states, we return nil and the ETA-bucketed labels
    /// take over. No brittle whole-string matching.
    fileprivate static func parseTrackOrderStatusPhrase(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        // Regex: after "Order <digits>: " capture up to the last " (" before " - ETA:"
        // Non-greedy phrase, greedy restaurant so nested parens in restaurant names
        // (rare but possible) don't break the parse.
        let pattern = #"^Order \d+:\s+(.+?)\s+\(.*\)\s+-\s+ETA:"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges >= 2,
              let phraseRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let phrase = String(text[phraseRange]).trimmingCharacters(in: .whitespaces)
        return phrase.isEmpty ? nil : phrase
    }

    /// Build an Order from an Instamart list row plus its live tracking data.
    /// Returns nil if the order isn't currently active.
    ///
    /// **Two lines, both Swiggy's own words.** `track_order` returns a headline
    /// and a partner-level detail, which map straight onto the row's bold
    /// status line and the smaller line above it:
    ///
    ///     SIDDANNA GOWDA has reached your location   ← status.subStatusMessage
    ///     Arrived at location                        ← status.statusMessage
    ///
    /// When there's no partner detail yet (early states) or it's gone
    /// (delivered), the small line falls back to store • items so the row
    /// still identifies which order it is.
    ///
    /// `get_orders`' own status fields are deliberately unused for display —
    /// they lag `track_order` by a stage. They stay as the fallback for when
    /// the tracking call fails.
    init?(instamart raw: InstamartOrderRaw, tracking: InstamartTrackingRaw?) {
        guard raw.isActive else { return nil }

        let store = raw.storeName ?? "Instamart"
        let itemNames = (raw.items ?? []).map { $0.name }
        let itemsLabel = itemNames.joined(separator: ", ")
        let itemsContext = itemsLabel.isEmpty ? store : "\(store) • \(itemsLabel)"

        // Headline: live tracking first, then get_orders' laggier fields.
        let headline = tracking?.status?.statusMessage
            ?? raw.statusMessage
            ?? raw.currentStatus

        // Small line: partner detail when Swiggy has one, else what was ordered.
        let context = tracking?.status?.subStatusMessage ?? itemsContext

        // "13 mins" → 13. Anything unparseable → nil.
        let eta: Int? = raw.estimatedDeliveryTime
            .flatMap { $0.split(separator: " ").first }
            .flatMap { Int($0) }

        // Progress from the headline's keywords. Ordered most-complete first,
        // since a delivered order has also been picked up.
        //
        // Stepwise rather than ETA-interpolated like Food: Instamart's ETA is
        // a static string from get_orders, not a live countdown, so there's no
        // smooth signal to interpolate. ProgressBarView's spring still animates
        // the jumps between stages.
        let s = headline.lowercased()
        let progressFraction: Double
        if s.contains("delivered") {
            progressFraction = ProgressStage.delivered.fraction
        } else if s.contains("arrived") || s.contains("reached") || s.contains("nearby")
                    || s.contains("minutes away") || s.contains("arriving") {
            progressFraction = ProgressStage.nearby.fraction
        } else if s.contains("picked up") || s.contains("on the way") || s.contains("out for delivery") {
            progressFraction = ProgressStage.inTransit.fraction
        } else if s.contains("packed") {
            progressFraction = ProgressStage.packed.fraction
        } else {
            progressFraction = ProgressStage.placed.fraction
        }

        self.init(
            id: raw.orderId,
            platform: .instamart,
            context: context,
            status: headline,
            eta: eta,
            progress: progressFraction
        )
    }
}

// MARK: - MCP capture log (forensic JSONL for post-order analysis)
//
// Writes one JSON object per line to
// `~/Library/Application Support/Myles/captures/YYYY-MM-DD.jsonl`.
// Each entry has: timestamp, tool name, endpoint URL, arguments, and the
// full raw response envelope (including anything in `content[]` that our
// typed decoders drop). Fire-and-forget — write errors are swallowed so
// capture never blocks or breaks a real poll.
//
// Purpose: when Swiggy's MCP surface changes (or we suspect we're dropping a
// field), turn this on, place an order, then read the JSONL to see exactly
// what came over the wire — not just what our typed models decode. This is
// how we found the conversational status text hiding in `content[]`.
//
// ENABLEMENT
//   • DEBUG builds  → ON by default (dev loop convenience).
//   • RELEASE builds → OFF by default. Responses contain order history,
//     addresses, and item names, so the installed app shouldn't accumulate
//     that on disk unless explicitly asked.
//   • Either default can be overridden without a rebuild:
//         defaults write com.dharani.Myles MylesCaptureMCPResponses -bool true
//         defaults write com.dharani.Myles MylesCaptureMCPResponses -bool false
//     Read once at startup, so flip it then relaunch.
//
// RETENTION
//   One file per day (day computed at write time, so an app left running
//   across midnight rolls over correctly). Files older than `retentionDays`
//   are pruned once per launch, so an always-on capture can't grow forever.

private final class MCPCaptureLog: @unchecked Sendable {
    static let shared = MCPCaptureLog()

    /// UserDefaults key for the manual override described above.
    private static let enabledDefaultsKey = "MylesCaptureMCPResponses"

    /// Daily capture files older than this are deleted at launch.
    private static let retentionDays = 7

    /// Whether to write anything at all. Resolved once at init.
    private let isEnabled: Bool

    private let baseDir: URL?
    private let queue = DispatchQueue(label: "com.dharani.Myles.MCPCaptureLog")
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter

    private init() {
        // Build default: on in DEBUG, off in RELEASE. Overridable via
        // UserDefaults (absent key → keep the build default).
        #if DEBUG
        let buildDefault = true
        #else
        let buildDefault = false
        #endif
        if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        } else {
            self.isEnabled = buildDefault
        }

        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dayFormatter = DateFormatter()
        self.dayFormatter.dateFormat = "yyyy-MM-dd"

        // Don't even create the directory when disabled — a release install
        // that never turns capture on leaves no trace on disk.
        guard isEnabled else {
            self.baseDir = nil
            return
        }

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Myles")
            .appendingPathComponent("captures")
        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.baseDir = dir

        if let dir {
            pruneOldCaptures(in: dir)
        }
    }

    /// Delete daily capture files older than `retentionDays`. Runs once per
    /// launch on the capture queue so it never blocks startup.
    private func pruneOldCaptures(in dir: URL) {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 24 * 60 * 60)
        queue.async {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
            for file in files where file.pathExtension == "jsonl" {
                guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate else { continue }
                if modified < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    func append(tool: String, endpoint: URL, arguments: [String: Any], responseJSON: Data) {
        // `baseDir` is nil whenever capture is disabled, so this single guard
        // covers both the disabled case and a failed directory lookup.
        guard let baseDir else { return }

        // Snapshot values before dispatching — [String: Any] isn't Sendable.
        let snapshot: [String: Any] = [
            "timestamp": isoFormatter.string(from: Date()),
            "tool": tool,
            "endpoint": endpoint.absoluteString,
            "arguments": arguments,
            "response": (try? JSONSerialization.jsonObject(with: responseJSON)) ?? "<unparseable>"
        ]
        let today = dayFormatter.string(from: Date())

        queue.async { [baseDir] in
            let fileURL = baseDir.appendingPathComponent("\(today).jsonl")
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot) else { return }

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            if let newline = "\n".data(using: .utf8) {
                try? handle.write(contentsOf: newline)
            }
        }
    }
}
