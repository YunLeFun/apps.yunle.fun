# Server-driven Host SSO Requirements

## Problem

The Apps native package currently embeds the set of SSO-capable applications.
Adding a reviewed SSO client therefore requires a new iOS/Android package even
though the authorization server already owns and enforces the production Client
Registry.

## Scope

- Move mutable client resolution and consent metadata to the central
  `sso-ticket` function.
- Keep the native host responsible for collecting the actual WebView origin,
  presenting consent, and returning a one-time code.
- Keep exact Registry validation at both resolution and code issuance.
- Make identity-change notification generic for first-party hosted pages.
- Preserve standard browser SSO as the compatibility fallback.

## Non-goals

- Publishing a new native package or deploying the CloudBase function in this
  change.
- Trusting marketplace records, parent-domain membership, or page-supplied
  display metadata as authorization policy.
- Sending host access tokens, refresh tokens, or reusable credentials to an
  embedded application.

## Acceptance criteria

1. When an embedded page requests host authorization, the system shall resolve
   the exact client, source origin, redirect URI, scope, nonce, and S256 PKCE
   challenge through the production Client Registry before prompting or login.
2. When resolution succeeds, the system shall derive application identity,
   icon, consent mode, and permission copy only from central trusted policy.
3. When a user approves authorization, the issuer shall revalidate the complete
   normalized request against the current Registry before issuing a short-lived,
   single-use code.
4. If a page changes any bound field or the Registry disables the client between
   resolution and issuance, the issuer shall reject the request.
5. When a future client is added to the central Registry, a compatible Apps
   package shall authorize it without embedding or updating a client allowlist.
6. When an older Apps package rejects an unknown host binding, the application
   shall fall back to top-level browser SSO; explicit user denial shall not
   trigger a redirect.
7. When the Apps identity changes, the native host shall notify every active
   hosted page, and each identity-aware application shall clear its own session.
8. Marketplace publication shall not grant SSO access, and removing a marketplace
   listing shall not silently alter central SSO policy.
