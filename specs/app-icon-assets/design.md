# App Icon Assets Design

## Asset contract

```ts
interface AppIconAssetVariants {
  src: string
  darkSrc?: string
}

interface AppIconAssets {
  appIcon?: AppIconAssetVariants
  mark?: AppIconAssetVariants
}
```

`AppRecord` and submission snapshots add `iconAssets`. The existing `logo` field remains as a read-compatible legacy fallback. New form submissions write both fields only when needed for compatibility; public projections expose both.

## Rendering

- `app-icon`: fills the square canvas and receives exactly one rounded platform mask. Brand pixels are not recolored and liquid-glass overlays are disabled.
- `mark`: uses a transparent square canvas. The image is rendered with `object-fit: contain`; uploaded marks are normalized conceptually against the `6 6 52 52` reference safe area and the UI exposes a guide in preview.
- Generated styles prefer `mark`; without a mark they preserve `app-icon` rather than attempting to recolor or extract it.
- Default assets select `darkSrc` only while the current color mode is dark. Missing dark assets fall back to `src`.
- Legacy `logo` is treated as a complete visual for compatibility. Existing data therefore does not suddenly gain or lose padding.

## Upload architecture

The current CloudBase storage bucket uses `ADMINWRITE`. Uploads therefore use a trusted Nitro endpoint instead of granting browser write access:

1. The form posts multipart data to `/api/apps/icon-assets` through the authenticated `$api` client.
2. The endpoint requires a non-anonymous, active CloudBase user with a verified phone number.
3. It accepts one `file` and an `assetRole` of `app-icon` or `mark`.
4. The browser accepts PNG, WebP, and passive SVG up to 5 MiB, rejects active SVG constructs, and rasterizes the result to a 1024×1024 PNG. Subject marks are alpha-bounds cropped and centered within an 80% safe area; complete icons must be near-square and fill the output canvas.
5. The endpoint independently accepts only PNG output up to 4 MiB and verifies the PNG signature, IHDR location, and exact 1024×1024 dimensions.
6. The endpoint rate-limits each user, uploads bytes to `app-icons/<hashed-uid>/<uuid>.png` with the Node SDK, and returns the stable `cloud://` file ID.

The form stores the stable file ID. Rendering resolves CloudBase file IDs with the same public origin mechanism already used for avatars.

## Form UX

- Replace the single Logo URL block with an icon-assets editor.
- Complete icon: recommended, URL entry plus file picker.
- Subject mark: optional, URL entry plus file picker.
- Dark variants: optional and collapsed behind a theme-specific section.
- A two-up light/dark preview explains which asset is active and shows the safe-area guide for marks.
- Existing `logo` values remain visible as a labeled compatibility fallback until the owner adds a typed asset or clears the old value.

## Compatibility and migration

- Normalizers accept missing `iconAssets`.
- `recordToAppInfo` exposes `iconAssets`; shared renderer reads it when available.
- `logo` remains in public output until all consumers upgrade.
- Asset-role selection is isolated in `resolveAppIconPresentation`; a later official-slug mapping can feed canonical `@yunlefun/icons` assets into the same contract without changing database records.

## Security

- Server-side authentication is required for upload.
- The server owns the CloudBase storage credential boundary.
- File names are generated; user filenames never become storage paths.
- SVG input is decoded and inspected before rasterization; active content and external references are rejected and SVG bytes are never stored.
- Upload failures are returned to the client and never converted into placeholder URLs.

## Verification

- Unit tests cover normalization, legacy fallback, light/dark resolution, and upload validation.
- Component tests cover complete-icon versus mark rendering.
- Typecheck, lint, unit tests, and production build must pass.
- Browser checks cover `/workshop/new`, `/workshop/:slug/edit`, `/tabs/home`, and one adjacent catalog/list surface.
