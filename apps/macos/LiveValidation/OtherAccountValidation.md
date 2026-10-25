# Other-account system browser validation

`../scripts/verify_other_account_sso.sh` does nothing online by default. The
explicit `--run-managed-accounts` entry stages only the two permitted managed
accounts, runs `MacOtherAccountLiveTests`, and prints the independent run UUID.
The ordinary macOS test scheme does not include this target.

The fixture uses the real AI 春联 consumer login UI, native consent presenter,
`ASWebAuthenticationSession`, bridge and authorization issuer. The operator
clicks the consumer, native and system-browser controls. The fixture never
issues a synthetic page authorization request or supplies a callback.

Read the pending instruction with `--status RUN_UUID`. After observing the
requested result, use `--ack RUN_UUID STAGE OBSERVATION` with the exact stage and
observation returned by status. A random nonce binds each acknowledgement to
one pending phase. Each phase waits at most 600 seconds; the whole test allows
3600 seconds to accommodate operator work and context handoffs. The production
system authentication session still has its separate 300-second timeout.
Acknowledgements are visible UI evidence, not proof of a callback;
the fixture independently checks the consumer's fresh remote identity.

The stages cover first cancellation, real login B while host A stays unchanged,
consumer logout followed by another cancelled system login, another real login
B, host logout/profile retirement/guest isolation, and host A login in a new
consumer profile. The final native current-account authorization verifies A.
Each new system-browser login must show empty fields, providing an observable
check of ephemeral browser isolation. B is never selected or saved in the host
AccountStore. A separate journaled native probe reads B's expected identity and
immediately signs itself out.

External accessibility clients can keep a detached WKWebView alive after the
runtime releases it. The live sign-out check therefore requires empty runtime
page/session collections and an old view detached from its window and superview.
If that view still exists, it must contain an empty `about:blank` document, with
the old JavaScript realm marker and authorization bridge gone. This verifies
termination of the account's document without claiming immediate deallocation
under accessibility observation. A separate ordinary runtime test retains the
view explicitly, verifies the empty document and removed bridge/handler/state,
then drops that reference and requires the weak reference to become nil.

The consumer's inspected production singleton is exported by
`/_nuxt/X4HmLciw.js`. Its own session token stays inside the page and is used for
a `no-store` GET to its configured CloudBase gateway `/auth/v1/user/me`.
Only HTTP status and an identity-match boolean return to native code. Anonymous
assertions require an actual HTTP 401; timeouts, SDK errors and other statuses
fail the test. If that public module changes, inspect the new deployment before
updating the reference. Never substitute a cached display name for this check.

Cleanup separately verifies consumer SDK logout (or an already empty session),
the empty consumer session's anonymous HTTP 401, successful native sign-out API
calls for the exact journal entries, and removal of only the recorded named
WebKit stores. Reports distinguish `consumerSDKSignOutComplete` from
`consumerAnonymousRemoteCheckComplete`: an unauthenticated request receiving
401 does not prove that the previous access token has been revoked. Successful
native sign-out API calls also do not establish immediate rejection of every
previous token. Cleanup viewers also load an empty document and detach from the
window. If accessibility still retains one, the same empty-document and removed
bridge checks must pass; the diagnostic records the retained object without
claiming deallocation. The first process records each confirmed consumer cleanup
and its process ID, releases its page ownership, and exits normally. The script
always launches a new purge process,
which requires those exact UUID proofs and a different process ID, and calls
public WebKit removal without opening a named store or loading a consumer URL.
Only successful purge removes the checkpoint directory and allows the whole
script to succeed. Remote-cleanup reports explicitly retain
`ownedWebsiteStoresRemoved: false` and `pendingStorePurge: true`; the separate
purge report must confirm actual removal. It deletes only the run's draft key.
An interrupted run retains UUID checkpoints and unique Keychain recovery
entries; retry with `--cleanup RUN_UUID`, which resumes at purge if the SDK,
anonymous-request and native sign-out checks are already confirmed. Raw logs and
xcresults are private temporary files; persisted reports contain safe stages,
booleans, statuses, UUIDs and sanitized compiler diagnostics.

Every phase must produce exactly one passed test, zero failed or skipped tests,
and a fresh report matching the run UUID and phase. A journey additionally needs
`journeyPassed: true`; purge needs zero remaining profiles and successful store
removal in a different process. A missing report, skipped test or partial purge
fails the script. Cleanup still runs after a failed journey and preserves its
original failure status.

The central system-browser session has a distinct cleanup boundary. Its real
credentials and CloudBase device ID are not exposed by
`ASWebAuthenticationSession`. The central page issues its callback without a
remote logout, and this repository does not establish the production server
session expiry. Reports therefore always state
`centralSessionRemoteRevocation: "not-observed"`; ephemeral browser closure or
empty fields in a subsequent window must not be described as remote revocation.
This test never revokes every device or changes server session policy.

## Validated run

On 2026-10-24, run `EBE3FC64-CE4E-47E2-8E94-CE9D00E2BE7A` completed all 12
stages using the real AI 春联 UI, native consent and Chrome 155 on macOS 26.6.2.
The journey and fresh-process purge each reported one passed test, zero failures
and zero skips; the script exited with status 0. The journey confirmed consumer
B with unchanged host A, cancellation, website logout and relogin, host logout,
guest isolation, and host A authorization in a new profile. All three recorded
stores were removed, the run directory was absent, and exact queries confirmed
that both run-owned Keychain items were absent.

Reports are in `../build/validation/other-account-sso/EBE3FC64-CE4E-47E2-8E94-CE9D00E2BE7A/`.
The successful result retains `centralSessionRemoteRevocation: "not-observed"`.
Earlier failed journeys and cleanup recovery remain documented in
`../validation.md`; they are not counted as successful script runs.
