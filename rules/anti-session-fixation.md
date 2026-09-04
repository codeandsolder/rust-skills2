# anti-session-fixation

> Rotate session IDs when authentication or privilege changes so a pre-authentication identifier cannot inherit elevated state.

## Why It Matters

A server-side session identifier is itself a capability. Before login it may legitimately identify low-privilege state such as a CSRF synchronizer token, locale, or an anonymous cart. If authentication simply adds privileged state to that same session record, anyone who learned or planted the pre-authentication ID can inherit the authenticated session after the victim logs in.

That is session fixation. Strong passwords, secure cookies, and CSRF protection do not fix it: the problem is preserving an already-known capability across a privilege boundary.

## Rotate at Privilege Boundaries

Whenever a session transitions from unauthenticated to authenticated, or gains materially stronger privileges, replace its identifier before attaching the elevated state.

A safe sequence is:

```text
validate credentials / authorization
load the existing pre-authentication session if needed
rotate the session identifier
attach authenticated or elevated state
persist the rotated session
return the new session cookie
```

Do not rotate only after adding the privileged state if the framework could persist the intermediate session. Keep the privilege transition and the identifier change in the same controlled operation.

Many session libraries expose this directly. For example, `tower-sessions` provides `Session::cycle_id()`, which retains session data while assigning a fresh ID and deleting the old stored record. Prefer the framework's supported rotation primitive over manually copying session maps between IDs.

## Preserve Intended Pre-Authentication State

Rotation does not have to mean throwing away all anonymous state. A normal login flow may need to retain a CSRF token, locale, return URL, cart contents, or other explicitly approved data.

The invariant is narrower:

> The old session identifier must not remain a capability for the post-authentication session.

Be deliberate about which pre-authentication values survive the transition. Never blindly promote attacker-controlled session data into authorization decisions merely because the identifier was rotated.

## Treat Rotation Failure as Login Failure

If session-ID rotation fails, do not continue and attach authenticated state to the old ID. The authentication operation has not safely completed.

If other durable credentials were already created before the failure—refresh tokens, API keys, device grants, or similar capabilities—roll them back or neutralize them before returning the error. Also clear any pending privileged session state that deferred middleware could still persist later.

This is the same multi-artifact issuance problem covered by [`err-anyhow-app`](./err-anyhow-app.md): propagating an error does not undo an earlier side effect.

## Test the Exact Stale Identifier

A useful regression test keeps the pre-authentication cookie and tries it again after login:

```text
1. create a pre-authentication session and capture cookie A
2. log in while presenting cookie A
3. assert the response issues cookie B and A != B
4. call an authenticated/session-inspection endpoint with cookie A
5. assert cookie A has no authenticated identity
6. call the same endpoint with cookie B
7. assert cookie B has the expected authenticated identity
```

Checking only that the login response contains a new `Set-Cookie` header is insufficient. The old identifier must actually be unusable for the elevated state.

Repeat the same stale-capability principle for logout, privilege revocation, password reset, and token rotation: retain the exact old credential and prove that using it no longer grants the revoked capability.

## Multiple Authentication Boundaries

Rotate again when the privilege change is meaningful enough that a previously exposed identifier should not span it. Examples include:

- anonymous to authenticated;
- ordinary user to administrator or sudo/re-authenticated mode;
- account recovery completing and restoring normal access;
- switching security principals inside one browser session.

Do not rotate on every ordinary request. Rotation is for capability boundaries, not as a substitute for secure random session IDs or appropriate cookie settings.

## See Also

- [`err-anyhow-app`](./err-anyhow-app.md) - compensate multi-step issuance failures and neutralize deferred state
- [`test-integration-dir`](./test-integration-dir.md) - exercise stale capabilities and canonical external contracts
