# Package presentation assets

These are original illustrated UI previews, **not simulator or device captures**.
The fictional Field Notes interface explains the package concepts. The source
example app uses different diagnostic widgets. Native iOS 27.1 behavior still
requires SDK compilation and device validation; smooth motion in the GIF is
illustrative and does not claim synchronized native animation.

| Asset | Purpose | Dimensions |
| --- | --- | --- |
| `hero.png` | README introduction / package banner | 1440 × 900 |
| `layout-modes.png` | Split/span comparison / pub.dev screenshot gallery | 1440 × 1010 |
| `layout-preview.gif` | Loop: split, span, reserved regions, native toolbar | 1000 × 710 |

The GIF loops for about 11 seconds. All three assets are individually below
0.5 MB. The branding banner is excluded from `pubspec.yaml` screenshots;
the two UI illustrations include explicit experimental-preview labels.

Regenerate from the package root:

```sh
python3 -m venv /tmp/iphone-duo-media-venv
/tmp/iphone-duo-media-venv/bin/pip install -r tool/media-requirements.txt
/tmp/iphone-duo-media-venv/bin/python tool/generate_media.py
```

Uses installed Avenir Next on macOS, or DejaVu Sans on Linux. Fonts are not
redistributed. Colors, icons, terrain and UI geometry are drawn by the script;
there are no external image assets. Use `--qa` to also export animation keyframes.

The README uses absolute GitHub raw image URLs so the artwork can display on
GitHub and pub.dev. Gallery paths in `pubspec.yaml` point to packaged local files.

Pub.dev accepts PNG/GIF screenshots up to 4 MB each; screenshot descriptions must
be no longer than 160 characters. See [pubspec screenshots](https://dart.dev/tools/pub/pubspec#screenshots).
