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
| 2 | UI design + iteration in Figma until locked | ✅ Done |
| 3 | macOS-native polish review on the locked design | ✅ Done (folded into Phase 4) |
| 4 | Build the app (Swift + SwiftUI + MenuBarExtra) — also a learning phase | ✅ Done |
| 5 | Local daily-use testing until reliable | **In progress** |
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

### Phase 2–3 — UI design + native polish (done)
- All popover states designed in Figma and built to spec: auth (fresh / expired / authorizing / failed), orders (loading / empty / loaded / error-cold / error-mid-order / delivered).
- macOS-native review happened inline during the build rather than as a separate pass.

### Phase 4 — Build (done)
- **Data layer:** `MCPClient` speaks MCP directly (no `mcp-remote`). Per-platform soft-fail — if Food errors but Instamart succeeds, the user still sees what's available; a 401 anywhere forces re-auth. `OrdersPoller` respects Swiggy's own `pollIntervalSec`, clamped to [10s, 300s].
- **Status copy comes from Swiggy, not from us.** Food reads the conversational phrase out of `track_food_order`'s `content[]` prose channel (the field we were previously discarding); Instamart uses `statusMessage`. Our own ETA-bucketed labels remain only as a fallback, worded to match Swiggy's so a fallback is invisible.
- **Motion:** ETA badge is a slot-machine reel (tall VStack clipped to one row, spring-animated offset). Progress bar interpolates continuously from ETA for Food rather than jumping between fixed stages.
- **Delivered celebration:** 60s "Order Delivered :)" window after the last active order clears, cancelled early if a new order arrives.
- **Forensic capture:** every raw MCP response can be appended as JSONL to `~/Library/Application Support/Myles/captures/`. On in Debug, off in Release, overridable via `defaults write com.dharani.Myles MylesCaptureMCPResponses -bool true`, 7-day retention. This is what surfaced the hidden `content[]` status text.
- **Live-tested end to end** against a real Food order — full lifecycle from placement through delivery and celebration.
- Renamed from Northern Lights → Myles.

### Phase 5 — Local daily-use testing (in progress)
- ✅ Archived, exported, installed to `/Applications`
- ✅ Keychain persists across the signing-context change (no entitlement needed)
- ✅ Launch at login working via `SMAppService` (⋯ menu toggle)
- ✅ App icon in Finder / Spotlight / Login Items
- ⬜ Instamart live-order test (Food is done; Instamart's copy fix has never been exercised on a real order)
- ⬜ Cancelled-order behaviour — never observed; current logic would incorrectly show the delivered celebration
- ⬜ Long restaurant names crowd out the item name on the context row
- ⬜ Right-click menu on the menu bar icon — needs dropping `MenuBarExtra` for a raw `NSStatusItem`; deliberately deferred until there's a stability baseline
- ⬜ Glass/material popover background — parked; composes muddily with the menu bar's own vibrancy
