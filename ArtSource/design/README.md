# Design source

A local copy of the Honest Chess design, read from claude.ai/design project
`f63fd12a-e2ba-4c22-be28-04afe3fd8f47` on 2026-09-27:

- `Honest Chess.dc.html`: every screen (splash, menu, vs-computer and
  two-player setup, board with promotion, pause and result overlays,
  statistics, settings, how to play, about the app, about Honest Arcade), the
  brand sheet, and the prototype's game logic.
- `support.js`: the design runtime the HTML loads. Generated, not ours to edit.

This is a reference, not the source of truth once a screen is built: the app
under `lib/` wins where they differ, and a deliberate difference is logged in
`.n8/decisions.md`. The project also holds two logo screenshots
(`screenshots/logo.png`, `screenshots/logo2.png`) that are not copied here.
