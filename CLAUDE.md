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
