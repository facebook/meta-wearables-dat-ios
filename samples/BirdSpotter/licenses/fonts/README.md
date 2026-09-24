# Bundled font licenses

BirdSpotter ships four typefaces in the app binaries. All are **SIL Open Font License 1.1**.

| Family | Copyright | Upstream |
|---|---|---|
| Libre Caslon Display | 2012 The Libre Caslon Display Authors | [impallari/Libre-Caslon-Display](https://github.com/impallari/Libre-Caslon-Display) |
| Libre Caslon Text | 2012 The Libre Caslon Text Authors | [impallari/Libre-Caslon-Text](https://github.com/impallari/Libre-Caslon-Text) |
| Public Sans | 2015 The Public Sans Project Authors | [uswds/public-sans](https://github.com/uswds/public-sans) |
| Cinzel | 2020 The Cinzel Project Authors | [NDISCOVER/Cinzel](https://github.com/NDISCOVER/Cinzel) |

## What the OFL requires of us

- **Bundling in the apps is fine**, including commercially and in closed-source builds. No runtime call-home, no attribution required in the app UI.
- **Redistributing the font files requires shipping the license.** This repository is public and contains the binaries, so the full `OFL-*.txt` for each family lives in this directory. That is the obligation that actually binds.
- **No Reserved Font Names are declared** by any of the four, so the instanced static builds below keep their family names legitimately.
- The fonts may not be sold on their own. We don't.

## Where the files are

```
BirdSpotter/Resources/Fonts/     static instances (SwiftUI faux-bold)
```

The iOS statics are generated from the upstream variable files with `fontTools.varLib.instancer`
at named instances only, with `updateFontNames=True`. That rewrites the name table, which is why
the PostScript names read `PublicSansRoman-Regular` rather than `PublicSans-Regular`.

Bird photography and audio have separate provenance — see
[ATTRIBUTION.md](../ATTRIBUTION.md).
