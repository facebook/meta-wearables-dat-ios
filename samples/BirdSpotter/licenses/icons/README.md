# Bundled icon licenses

BirdSpotter draws every icon in the app from **Phosphor Icons**, except Identify, `shutter`,
the two `mark*` badge layers and the four `size*` anchors, which are our own drawing and carry
no third-party terms.

Nineteen drawings from `@phosphor-icons/core` **2.1.1**, copyright 2023 Phosphor Icons,
[phosphor-icons/core](https://github.com/phosphor-icons/core): `binoculars`, `book-open-text`,
`caret-left`, `caret-right`, `check`, `compass`, `eye`, `gear` (two weights), `info`, `lightning`,
`lightning-slash`, `magnifying-glass`, `map-pin`, `pause`, `play`, `question`, `waveform`, `x`,
`x-circle`. `gear` is used at two weights, so those nineteen drawings fill twenty roles. The full
role-to-drawing table lives in `assets/glyphs/README.md`.

Identify and the `markRings` / `markBird` badge layers are cut from
`assets/icon.svg` — ours. `shutter` is ours, drawn on the 24-grid.

The four `size*` anchors — `sizeSparrow`, `sizeRobin`, `sizeCrow`, `sizeGoose` — are ours,
drawn from photo reference in a shared 64 × 56 box rather than on the 24-grid. Sparrow → robin
→ crow → goose is the ordinary field-guide size ladder and belongs to no one guide, but the
*drawings* are original: no other app's artwork was traced, referenced or vectorized.

## What the MIT license requires of us

- **Bundling in the apps is fine**, commercially and in closed-source builds. No attribution
  in the app UI, no runtime call-home.
- **The copyright notice must ship with any substantial portion of the software.** Nineteen
  drawings in a public repository is the case the clause is written for, so the full license text
  lives here as `MIT-phosphor.txt`. That is the obligation that actually binds.
- **Modification is permitted.** Each glyph was reduced from Phosphor's 256-unit grid onto a
  24-unit one and its path data flattened; no outline was redrawn.

## Why not SF Symbols

The obvious iOS answer is disqualified rather than merely unappealing: SF Symbols is licensed
only for user interfaces running on Apple operating systems, and Apple sells no cross-platform
license. Phosphor's MIT license permits redistribution of the bundled artwork.

## Where the files are

```
BirdSpotter/Assets.xcassets/Glyph*.imageset/
```

Fonts have separate provenance — see [`licenses/fonts/`](../fonts/). Bird photography and audio
have their own — see [ATTRIBUTION.md](../ATTRIBUTION.md).
