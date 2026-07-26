# Myles

A macOS menu bar app that shows real-time Swiggy delivery status (Food + Instamart) at a glance — without opening the app or getting distracted by notifications.

> Previously known internally as **Northern Lights** — you may still see that name in a few historical places (repo folder, Xcode project file) until those get renamed on their own passes.

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
Myles/
├── Myles.xcodeproj
├── Myles/
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
| 1 | Design system foundation in Figma — Swiggy color palette (neutrals + brand) via Mobbin MCP + Instamart screenshots | ✅ Done |
| 2 | UI design + iteration in Figma until locked | Next |
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

### Phase 1 — Design system foundation (done)
- Two-layer token architecture set up in Figma file [Northern Lights](https://www.figma.com/design/c7n5cGRk7K58InDqqWSZVL/Northern-Lights)
- **`NL — Primitives`** (42 variables): full tonal ramps (50–900) for Neutral, Swiggy Orange, Instamart Blue, Status Green — plus extended neutrals (0, 1000)
- **`NL — Semantic`** (25 variables): functional tokens aliased to primitives — Brand · Swiggy, Brand · Instamart, Status, Text, Surface, Border
- **Anchor colors:**
  - Swiggy Orange `#FF5200` (HSL 19°, 100%, 50%) — official brand
  - Instamart Blue `#0051FF` (HSL 221°, 100%, 50%) — eyedropped from current Instamart app
  - Status Green `#25B159` (HSL 142°, 65%, 42%) — kelly green family used across CTAs and veg indicators
  - Neutrals — Tailwind-style cool grey ramp
- Ramps generated via HSL math with hue locked across each scale
- Visual swatch sheet lives in `🎨 Palette Preview` section (x=16000) for quick review
