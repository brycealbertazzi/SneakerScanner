# SneakScan landing page

Marketing site for SneakScan, intended for `sneakscan.com`. Next.js (App Router) +
Tailwind v3, structured to mirror [getspendview.app](https://getspendview.app) so the two
Albertazzi Labs sites stay consistent.

```bash
npm run dev     # http://localhost:3000
npm run build   # production build — all routes prerender to static HTML
npm start       # serve the production build
```

## Routes

| Route | Contents |
|---|---|
| `/` | Hero (demo video) → 6-card feature grid → 4 screenshot deep-dives → download CTA |
| `/privacy` | Privacy Policy |
| `/terms` | Terms of Service |

The legal routes replace the old `privacy.sneakscan.com` / `terms.sneakscan.com`
subdomains. The app links to those subdomains from
`lib/screens/paywall_page.dart` (lines ~856 and ~897) — **update those to
`https://sneakscan.com/terms` and `https://sneakscan.com/privacy`, or keep the
subdomains alive as redirects**, otherwise the in-app links break.

## Editing content

Nearly all copy lives in two files; the components are just layout.

- `lib/content.ts` — headlines, feature cards, deep-dive sections, store URLs, support email.
- `lib/legal.ts` — privacy and terms text, as structured sections.

## Design tokens

Set in `tailwind.config.ts`:

- `brand` `#BA6A37` — SneakScan's in-app accent (`0xFFBA6A37` in `lib/`)
- `page` `#F2F2F7` — page background behind the white cards

`components/PhoneFrame.tsx` is the device bezel used six times across the page. It takes
a `screenAspect` so content is never cropped: `SCREENSHOT_ASPECT` (1284×2778) for the app
screenshots, `VIDEO_ASPECT` (9:16) for the hero demo.

## Assets

`public/` is generated from sources elsewhere in the repo. To regenerate, from the repo root:

```bash
OUT=landing_page/public
SRC="ios/App Store Connect Assets/orange"

# Screenshots → WebP at 660px wide
ffmpeg -y -i "$SRC/HomePage.PNG"    -vf scale=660:-2 -quality 82 $OUT/scan-screen.webp
ffmpeg -y -i "$SRC/ScanDetails.PNG" -vf scale=660:-2 -quality 82 $OUT/details-screen.webp
ffmpeg -y -i "$SRC/GOAT.PNG"        -vf scale=660:-2 -quality 82 $OUT/market-screen.webp
ffmpeg -y -i "$SRC/ScanHistory.PNG" -vf scale=660:-2 -quality 82 $OUT/history-screen.webp

# Demo video. The source is HEVC/H.265, which Chrome and Firefox refuse to play in a
# <video> tag — it MUST be transcoded. -an because the hero autoplays muted.
ffmpeg -y -i assets/SSASCUpdatedDemoFinalized.mp4 -vf scale=720:-2 -c:v libx264 -profile:v high \
  -crf 26 -preset slow -pix_fmt yuv420p -an -movflags +faststart $OUT/demo.mp4
ffmpeg -y -i assets/SSASCUpdatedDemoFinalized.mp4 -vf scale=720:-2 -c:v libvpx-vp9 \
  -crf 34 -b:v 0 -an -row-mt 1 $OUT/demo.webm
ffmpeg -y -i assets/SSASCUpdatedDemoFinalized.mp4 -ss 0.5 -frames:v 1 -vf scale=660:-2 $OUT/demo-poster.webp
```

Total `public/` weight is ~3.5 MB, dominated by the two video encodes.

> **Use `assets/SSASCUpdatedDemoFinalized.mp4` (886×1920), not
> `assets/SSDemo19201080.mp4`.** They are the same 19-second recording, but the latter
> was center-cropped to 9:16 — it cuts off the app's top bar and its entire bottom
> button row. That crop is baked into the file and cannot be undone by resizing the
> phone frame. `VIDEO_ASPECT` in `components/PhoneFrame.tsx` is 886/1920 to match.

## Deploying

Every route is static, so this runs anywhere. On Vercel, point a project at this
subdirectory and it builds as-is.

To emit a plain static bundle instead (for Firebase Hosting, S3, or the host currently
serving sneakscan.com), add to `next.config.ts`:

```ts
output: "export",
images: { unoptimized: true },
```

then `npm run build` writes `out/`. Note that `images.unoptimized` disables `next/image`
resizing — the WebP files in `public/` are already sized for display, so this is fine.
