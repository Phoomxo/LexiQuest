# Public release checklist

## Public URLs

- Privacy: `https://vocab-learning-app-219ef.web.app/privacy/`
- Delete account: `https://vocab-learning-app-219ef.web.app/delete-account/`
- Support: `https://vocab-learning-app-219ef.web.app/field-support/`

Before deployment, approve the private-support and deletion-request hosts in the trusted `tool/cli/config/release-contact-policy.json`, copy that file exactly to deployable `hosting/public/release-contact-policy.json`, then provide `hosting/public/release-contact.json` from the owner-controlled release record. The trusted policy starts with both host lists empty so an unreviewed endpoint cannot become trusted through runtime configuration alone. The verifier uses these fixed repository paths; callers cannot substitute a temporary trust policy or contact file.

The contact file must contain schema version 1, the canonical privacy URL, approved HTTPS support/deletion URLs, a non-email data-controller name and the approved retention summary. URLs cannot contain user information, query strings, fragments, non-default ports or secret-like path segments. Optional reachability evidence records a UTC timestamp, successful HTTP status and private evidence reference; use `-RequireReachabilityEvidence` for a production gate.

This file is public configuration, not a credential; never place passwords, tokens, participant/study identifiers, personal email addresses or private evidence in it.

Run:

```powershell
pwsh -NoProfile `
  -File tool/cli/verify-public-release-pages.ps1 `
  -RequireReachabilityEvidence
```

The verifier must pass before Firebase Hosting deployment. Deployment, Play submission and production data collection still require explicit owner authorization and their separate evidence gates.
