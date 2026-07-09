# Native UI conformance

This pass aligns the existing non-history card UI with Home Assistant's current
frontend while retaining Swift-native controls and rendering. Visual parity is
approximate, not pixel-perfect.

## Aligned in this pass

- `CardHostView` / `CardChrome`: shared 16-point content insets, 12-point card
  radius, dynamic card surface color, and a one-point theme-like divider border.
- `EntityRowView`: a 40-point icon/state-badge column, 16-point separation from
  the name, 40-point minimum row height, single-line ellipsis for names,
  secondary text, and values, plus a platform pointer-hover affordance.
- `TileCardView`: 56-point minimum height, 10-point horizontal content inset and
  gap, a circular 36-point icon container, single-line tile text, and distinct
  active/inactive fill opacity driven by the existing state-color resolver.
- Shared spacing, card, row, and tile constants live in `CardViewSupport.swift`
  so later native UI can reuse them without introducing a broad design system.

## Intentionally deferred

- `CardHostView`: runtime HA theme overrides, backdrop-filter parity, raised-card
  shadows, per-card CSS custom properties, and web transition behavior.
- `EntityRowView`: exact browser font metrics, the full HA `state-badge`
  implementation (entity pictures and domain-specific badge rendering), web
  action ripple behavior, keyboard focus rings, and every specialized entity-row
  control.
- `TileCardView`: features, badges, entity pictures, vertical/inline layouts,
  custom tile colors, exact web hover/press/focus animation, and domain-specific
  animations.
- Chart and history UI, including chart rendering and visual conformance, remains
  deferred to Modules 10 and 11.
