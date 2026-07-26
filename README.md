# Myles

A small macOS menu bar app that shows where your Swiggy order is, without you having to open anything.

<!-- TODO: drop a screenshot of the popover here -->

## Why

I keep notifications off. All of them. Which is great for focus and terrible for knowing whether dinner is five minutes away or still being cooked — so I'd end up opening the Swiggy app every few minutes to check, which is exactly the kind of small distraction I turned notifications off to avoid.

Myles sits in the menu bar. One click shows the order, the ETA, and how far along it is. No notifications, no app switching, no chat interface. It's a glance, and then you go back to what you were doing.

## What it does

- Tracks active **Swiggy Food** and **Instamart** orders side by side
- Live ETA that counts down as the order gets closer
- The actual status text Swiggy uses — "Partner is on the way", "Out for delivery", "Arrived at location" — not a generic label
- A progress bar that moves continuously rather than jumping between a handful of fixed stages
- Sits quietly at "No active orders" the rest of the time

## How it works

Swiggy runs a [Builders MCP program](https://mcp.swiggy.com/builders/docs/) — an official API for building on top of Swiggy. Myles talks to it directly over MCP, authenticating through OAuth against your own Swiggy account. Your credentials never touch anything of mine; the token lives in your macOS Keychain.

One thing worth writing down, because it shaped the app: Swiggy's `orderStatus` field is only ever `processing` or `Delivered`, so early versions showed a vague "Order in progress" for the entire delivery. The good status text turned out to be sitting in the MCP response's prose channel the whole time — a field the client was throwing away as "text meant for LLMs". Reading it instead is why the status line now matches what you'd see on your phone. Worth remembering that the interesting data isn't always in the obvious field.

## Built with

- Swift + SwiftUI, native `MenuBarExtra`
- OAuth 2.1 with PKCE against Swiggy's MCP endpoints
- Design system built in Figma first, then ported to `Colors.swift` as a two-layer token setup (primitives → semantic), so the app and the Figma file stay in sync
- Written almost entirely with [Claude Code](https://claude.com/claude-code) — I'm a product designer, not an iOS engineer, and this was as much about learning Swift as shipping the app

## Status

Working and in daily use on my own machine. Food is tested end to end against real orders; Instamart works but has had less mileage.

Not distributed yet — Swiggy's Builders program is currently scoped to local development, so a public release is a conversation to have with them first, not something to just do. There's a `scripts/make-dmg.sh` for packaging when that time comes.

## Credits

Delivery illustrations and the Swiggy brand colours belong to Swiggy. This is an independent side project and isn't affiliated with or endorsed by them.
