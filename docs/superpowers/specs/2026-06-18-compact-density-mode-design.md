# Compact Density Mode

**Date:** 2026-06-18  
**Status:** Approved

## Goal

Add a toggle button that switches the board into a compact ("dense") view, reducing card padding and column widths so all columns fit on screen horizontally without scrolling.

## Approach

Use `data-density="compact"` on `.kb-shell` — the same pattern as `data-theme="dark"`. All compact CSS overrides are scoped under `[data-density="compact"]` in `laserfocus.css`. A new `density` Stimulus controller handles toggle and persistence via `localStorage`.

## Button

- Placed in `.kb-header-right`, immediately left of the theme toggle button
- Same style as `.kb-theme-btn` (icon-only, no label)
- SVG: compress icon when in normal mode (click → compact), expand icon when in compact mode (click → normal)
- `data-controller="density"`, `data-action="density#toggle"`

## Stimulus Controller (`density_controller.js`)

- On `connect()`: read `localStorage.getItem("kb-density")`; if `"compact"`, set `data-density="compact"` on `.kb-shell` and update button icon
- On `toggle()`: flip between `""` and `"compact"` on `.kb-shell`, persist to `localStorage`, sync button icon
- No interaction with board hash state — density is a local UI preference, not a shareable filter

## CSS Overrides

All rules scoped under `[data-density="compact"]` in `laserfocus.css`.

| Selector | Property | Normal | Compact |
|---|---|---|---|
| `.kb-col` | `min-width` | 220px | 160px |
| `.kb-col` | `max-width` | 360px | 240px |
| `.kb-col-head` | `padding` | 9px 10px | 5px 8px |
| `.kb-col-body` | `padding` | 8px | 5px |
| `.kb-col-body` | `gap` | 6px | 4px |
| `.kb-card` | `padding` | 8px 10px | 4px 7px |
| `.kb-card-row1` | `margin-bottom` | 5px | 2px |
| `.kb-card-row2` | `margin-top` | 7px | 2px |
| `.kb-card-title` | `font-size` | ~13px | 11.5px |
| `.kb-ladder` | `display` | block/flex | none |

## Files to Touch

1. `app/assets/stylesheets/laserfocus.css` — add compact CSS block
2. `app/javascript/controllers/density_controller.js` — new file
3. `app/views/board/show.html.slim` — add button and wire controller
