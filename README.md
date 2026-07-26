# Myles

Myles is a menubar app that helps you track your food and instamart orders. You don't have to open your phone each time to check the status of your order. Log in once with your mobile number and it's there in the menu bar.



## Why I built this

I use an Android phone and a Macbook from work. A lot of people I know are on some version of that split.

Every time I order through Swiggy, I have to open the app just to check my order status. It's a small thing, but it happens often, and each time it means unlocking my phone, opening the app, and navigating to the order — just to glance at one piece of information.

The status of my order should take a glance to check, not a full app-opening ritual.

That gap between "I want a glance" and "I have to do five steps for a glance" was the core problem. So I built Myles to close it.

## What it does

- Shows active Food and Instamart orders together
- Live ETA that counts down
- Swiggy's own status text — "Partner is on the way", "Out for delivery", "Arrived at location"
- A progress bar that moves smoothly instead of jumping between stages
- Says "No active orders" and stays out of the way the rest of the time

## How it works

Swiggy has an official API for developers, the [Builders MCP program](https://mcp.swiggy.com/builders/docs/). Myles talks to it directly. You log in with your Swiggy account through their own OAuth screen, and the token stays in your Mac's Keychain — nothing goes anywhere else.

**Polling is built to be a good API citizen.** Swiggy tells us how often to check via `pollIntervalSec`, and that tightens on its own as a delivery gets closer. Myles follows whatever it says rather than picking its own number.

When nothing is active, there's no point asking at the same rate, so it backs off:

| Situation | How often it checks |
|---|---|
| Live order | Whatever Swiggy asks for (10s–5min) |
| Idle, first 10 min | Every minute |
| Idle, 10–30 min | Every 2 minutes |
| Idle, 30+ min | Every 5 minutes |

The last piece is the one I like most. If the app has been idle for a while and you suddenly click the menu bar icon, that click means something — you're probably checking because you just ordered. So opening the popover cuts the timer short and polls immediately, instead of making you wait out the remaining four minutes of a backed-off cycle. It skips that if the last check was under 15 seconds ago, so opening and closing repeatedly doesn't hammer the API.

## Built with

- Swift and SwiftUI, native `MenuBarExtra`
- OAuth 2.1 with PKCE against Swiggy's MCP endpoints
- Design system built in Figma first, then ported to `Colors.swift` so both stay in sync
- Written almost entirely with [Claude Code](https://claude.com/claude-code). I'm a product designer, not an iOS engineer — this was as much about learning Swift as shipping the app

## Status

Working and in daily use on my own machine. Food is tested end to end against real orders; Instamart works but has had less mileage.

Not distributed yet — Swiggy's Builders program is currently scoped to local development, so a public release is a conversation to have with them first, not something to just do.

## Credits

Delivery illustrations and the Swiggy brand colours belong to Swiggy. This is an independent side project and isn't affiliated with or endorsed by them.
