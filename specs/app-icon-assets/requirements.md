# App Icon Assets Requirements

## Problem

The app catalog currently stores one ambiguous `logo` URL. The renderer therefore cannot distinguish a transparent subject mark from a complete app icon, so spacing, backgrounds, theme styling, and platform masking are inconsistent with the canonical YunLeFun icon rules.

## Scope

- Add explicit `mark` and `app-icon` assets, each with an optional dark variant.
- Keep legacy `logo` records readable and editable.
- Let an authenticated developer upload supported icon files without weakening CloudBase storage permissions.
- Render complete icons and subject marks with different composition rules.
- Preview the result in light and dark appearances before submission.

## User stories

1. As a developer, I can provide a complete app icon for faithful display on the home screen and in the catalog.
2. As a developer, I can optionally provide a transparent subject mark so YunLeFun appearance styles can compose it on generated backgrounds.
3. As an existing app owner, I can edit an old app without first migrating its `logo` manually.
4. As a user, I see consistent icon scale and masking in both light and dark appearances.

## Acceptance criteria

1. When an app has a complete icon, the system shall render it edge-to-edge inside one platform mask without applying a second background or brand-color overlay.
2. When an app has a subject mark and the selected icon style is generated, the system shall render the normalized mark inside the canonical safe area on the generated theme background.
3. When both asset types exist, the default/original presentation shall prefer the complete icon and generated presentations shall prefer the mark.
4. When only a legacy `logo` exists, the system shall preserve the current visible result and shall not discard the value during editing or submission.
5. When a verified developer uploads an icon, the client shall reject active SVG content and normalize supported input to PNG; the server shall independently validate authentication, role, PNG signature, file size, and 1024×1024 dimensions before storing it.
6. When an upload succeeds, the system shall persist a stable CloudBase file ID rather than a temporary signed URL.
7. When an upload fails validation or storage, the form shall show an actionable error and shall not replace the previous asset.
8. While editing icon assets, the form shall provide light and dark previews at home-screen scale.
9. When no dark variant is provided, the system shall reuse the default asset without applying automatic color inversion.
10. When a remote or uploaded image fails to load, the system shall fall back to the configured emoji.

## Constraints and non-goals

- Existing app IDs, installation records, review state, and publication state remain unchanged.
- Both asset types are supported, but only the complete icon is recommended; the mark and dark variants remain optional.
- This change does not deploy the app, mutate production app records, or relax the current CloudBase storage ACL.
- Automatic background removal or arbitrary raster-to-vector conversion is out of scope.
