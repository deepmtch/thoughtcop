# BUG-017 — Ticker background was not customizable

## Symptom

The resting ticker always used the system header material. Users could configure
speed, width, and position but could not choose a background color.

## Root cause

Ticker appearance was implicit in `NSVisualEffectView`; there was no persisted
color model or background layer behind the ticker content.

## Fix

- Add a dedicated `TickerBackgroundView` behind the source, ticker, and settings
  icon without changing the message or controls backgrounds.
- Add **Ticker Background…** to the settings menu using the native macOS color
  panel, including opacity.
- Persist colors as sRGB RGBA components.
- Add **Use System Ticker Background** to clear the custom color.
- Choose light or dark ticker foregrounds from relative luminance so labels and
  the settings icon remain readable.
- Publish background mode, RGBA values, and contrast mode in the local state API.

## Verification

`./.build/doublethink --ticker-background-selftest` verifies RGBA persistence, reset, and
light/dark contrast selection. Live `/background/blue` must show a blue 460 × 70
ticker with white foreground and `tickerBackgroundMode: custom`. After restart,
the RGBA values must persist. `/background/system` must restore the system
material and `tickerBackgroundMode: system`.
