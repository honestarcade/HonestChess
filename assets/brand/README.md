# Brand sources

Vector sources for the launcher icon, the pre-12 start screen mark and the
Play Store icon (#18). They are committed so builds never depend on access to
the design project. These are not app assets: nothing here is bundled.

Provenance: claude.ai/design project `f63fd12a-e2ba-4c22-be28-04afe3fd8f47`,
file `Honest Chess.dc.html` (local copy in `ArtSource/design/`), the brand
sheet's APP ICON card (dark tile, `#04213F`, radius 19 of 82). The rook path
and its `translate(32,32) scale(1.32) translate(-32,-32)` transform were
copied verbatim from its inline SVG on 2026-09-27. The light tile and the bare
studio badge on the same card are not shipped (owner, /n8-plan M0 round two).

| Source | Feeds | Notes |
|---|---|---|
| `icon-tile.svg` | `ArtSource/store/icon-512.png` | the APP ICON on a full-bleed `#04213F` square; Play applies its own mask |
| `icon-legacy.svg` | `mipmap-*/ic_launcher.png` (48–192 px) | the tile under the design's rounded corner (19 of 82 → 14.83 of 64), for Android 7 |
| `android-foreground.svg` | `mipmap-*/ic_launcher_foreground.png` (108–432 px), `drawable-*/launch_mark.png` (96–384 px) | the adaptive icon's foreground layer and the pre-12 start screen's mark; the icon background is `@color/ic_launcher_background` |
| `android-monochrome.svg` | `mipmap-*/ic_launcher_monochrome.png` (108–432 px) | Android 13 themed icon: corners and rook, white |
| `STUDIO-MARK.svg` | the launcher icon guard | the studio's shared four-corner group, copied from Honest Solitaire's |

Render with `tools/render_icons.sh`; `tools/render_icons.sh --check` re-renders
into `build/icon-check/` and lists byte differences. It needs `rsvg-convert`
(Homebrew `librsvg`) and `python3`. The committed outputs were rendered on
2026-09-27 with rsvg-convert 2.62.2 and Python 3.12.3.

**Studio mark.** The brand sheet's corners (`M 3 21 L 3 10 A 7 7 …`, stroke 6)
are exactly `STUDIO-MARK.svg`'s, the geometry Honest Solitaire's owner chose
for every studio app.

**Inline mark.** The corners-and-rook group sits between `mark:begin` /
`mark:end` markers, identically in the three coloured sources; the guard holds
them to one copy and their corners to `STUDIO-MARK.svg`.

**Safe zone.** In the foreground, the mark's 64-unit box spans 184 of 432 px
(46 of 108 dp), centred. The corners reach farthest: a corner's outer edge is
an arc of radius 7 + 3 (half the stroke) about a point 10 units in from the box
corner, so its farthest point sits (32 − 2.93) × √2 ≈ 41.1 units from the
centre: ≈ 29.5 dp, inside the 33-dp radius of the 66-dp safe zone. The rook,
scaled 1.32 about the centre, spans x 17.4–46.6 and y 9.6–53.4, so its
farthest corner is √(14.6² + 22.4²) ≈ 26.7 units from the centre — inside the
corners' reach. The guard recomputes the corners' reach from the files.
