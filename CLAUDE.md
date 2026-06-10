# Northern Lights

A macOS menu bar app that shows real-time Swiggy delivery status (Food + Instamart) at a glance — without opening the app or getting distracted by notifications.

## What this is

Passive utility app. Lives in the Mac menu bar. Polls Swiggy's MCP API to show active order status. No AI, no chat — just live delivery data in one click.

## Current scope

- Swiggy Food order tracking
- Instamart order tracking
- Local build only (single user — the developer's own Swiggy account)
- Production distribution is a later problem

## Tech stack

- **App:** Swift + SwiftUI (native macOS MenuBarExtra)
- **Data:** Swiggy Builders MCP API (mcp.swiggy.com)
- **Auth:** OAuth 2.1 with PKCE (user's own Swiggy account)

## Swiggy MCP tools we use

| Tool | Platform | Purpose |
|---|---|---|
| `track_food_order` | Food | Active food orders + status (no orderId needed) |
| `get_orders` | Instamart | Fetch active Instamart order IDs |
| `track_order` | Instamart | Real-time status per order (needs orderId + lat/lng) |

## Project structure (planned)

```
Northern Lights/
├── NorthernLights.xcodeproj
├── NorthernLights/
│   ├── App/
│   ├── MenuBar/
│   ├── Swiggy/          # MCP auth + API calls
│   └── Views/
```

## Key contacts

- Swiggy Builders: builders@swiggy.in
- Docs: https://mcp.swiggy.com/builders/docs/

## Roadmap

Macro plan. Each phase gets a detailed checklist when it starts — not before.

| Phase | Scope | Status |
|---|---|---|
| 0 | Swiggy MCP connection proof (Claude Desktop + OAuth + live tool calls) | ✅ Done |
| 1 | Design system foundation in Figma — Swiggy color palette (neutrals + brand) via Mobbin MCP + Instamart screenshots | Next |
| 2 | UI design + iteration in Figma until locked | — |
| 3 | macOS-native polish review on the locked design | — |
| 4 | Build the app (Swift + SwiftUI + MenuBarExtra) — also a learning phase | — |
| 5 | Local daily-use testing until reliable | — |
| 6 | Record demo, pitch to Swiggy Builders for production access | — |

Operating principle: **phase-by-phase zoom-in.** No pre-planning of phase internals.

## Progress log

### Phase 0 — MCP connection proof (done)
- Connected Swiggy Food + Instamart MCPs to Claude Desktop via `mcp-remote`
- OAuth completed against real Swiggy account
- Verified live data flow:
  - `get_orders` (Instamart) → returned real past orders with full details
  - `get_addresses` (Food) → returned all 9 saved addresses
  - `track_food_order` → returns active orders (currently none)
- Conclusion: data foundation works. Ready to design.
