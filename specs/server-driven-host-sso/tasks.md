# Implementation Plan

- [x] 1. Add trusted presentation metadata to authorization decisions
  - Project the client icon without accepting caller-supplied display fields.
  - Cover exact origin, redirect URI, and scope behavior.
  - _Requirements: 1, 2, 8_

- [x] 2. Add the central authorization resolver
  - Normalize the request through the existing Registry validation path.
  - Return a binding that the Apps shell can compare field for field.
  - Keep code issuance as an independent second validation pass.
  - _Requirements: 1, 2, 3, 4_

- [x] 3. Replace the embedded Apps authorization Registry
  - Resolve pending native requests through `sso-ticket`.
  - Parse and bind the response before login, consent, or issuance.
  - Remove generated Registry artifacts and build-time synchronization.
  - _Requirements: 2, 5, 8_

- [x] 4. Generalize identity-change propagation
  - Notify every active hosted page without sending account data.
  - Keep native deletion only for existing legacy session cookies.
  - Make Dayun revoke its own BFF session on the event.
  - _Requirements: 7_

- [x] 5. Verify compatibility and production artifacts
  - Run targeted and full tests, type checks, lint, and production builds.
  - Verify old-host fallback and explicit-denial behavior.
  - Perform CloudBase security review and document rollout order.
  - _Requirements: 3, 4, 5, 6, 7, 8_
