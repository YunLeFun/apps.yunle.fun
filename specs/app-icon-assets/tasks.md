# Implementation Plan

- [x] 1. Define requirements and architecture
  - Record the asset roles, compatibility rules, upload boundary, and validation contract.
  - _Requirements: 1–10_

- [x] 2. Upgrade shared data contracts
  - Add typed icon assets to records and submission snapshots.
  - Normalize server input and public projections while preserving `logo`.
  - _Requirements: 3, 4, 9_

- [x] 3. Add the secure upload path
  - Validate multipart files and SVG safety.
  - Upload through the CloudBase Node SDK and return a stable file ID.
  - _Requirements: 5–7_

- [x] 4. Upgrade icon rendering
  - Resolve light/dark variants and distinguish complete-icon from mark composition.
  - Preserve legacy image and emoji fallbacks.
  - _Requirements: 1–4, 9, 10_

- [x] 5. Upgrade create/edit UX
  - Add URL and upload controls for both roles and optional dark variants.
  - Add light/dark previews and mark safe-area guidance.
  - _Requirements: 1, 2, 5–9_

- [x] 6. Verify and review
  - Add focused tests and run typecheck, lint, unit tests, and build.
  - Exercise affected and adjacent routes in a browser.
  - Run the CloudBase code-review checklist and fix findings.
  - _Requirements: 1–10_
