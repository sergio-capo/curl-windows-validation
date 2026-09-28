# curl on Windows: reproducible tutorial checks

This repository contains only public test code and dummy data for checking the
[curl introduction article](https://qiita.com/s_horikoshi/items/d2dde6afc568d30b8d2a).
It does not contain the article's source repository, business documents, tokens,
or other credentials.

## Scope

The GitHub Actions workflow runs on the standard `windows-2025` runner with:

- Windows PowerShell (`shell: powershell`) and PowerShell 7 (`shell: pwsh`).
- The runner's default `curl.exe` lookup and Windows' `System32/curl.exe`.

Each job records the OS, PowerShell version, resolved curl executable and version,
and the `curl` alias, if present. This is Windows Server VM validation, not testing
on a physical Windows 11 PC.

Tests cover GET, response headers, HEAD, query parameters, JSON POST, the explicit
JSON-header alternative, and HTTP 404 with and without `--fail-with-body`.
The script asserts response data and exit codes rather than checking only whether
the workflow completed. A UTF-8 file without a BOM supplies the same dummy JSON
as the article. POST uses the public JSONPlaceholder practice API, which simulates
creation without persisting the resource. The illustrative authentication command
is intentionally not executed.

## Run

Open **Actions → Windows curl validation → Run workflow**, or push a relevant
change to `main`. In a local Windows PowerShell or PowerShell 7 session:

```powershell
./scripts/Test-CurlArticle.ps1 -CurlSelection path
./scripts/Test-CurlArticle.ps1 -CurlSelection system32
```

The script requires curl 7.82.0 or newer, HTTPS access to
`https://jsonplaceholder.typicode.com`, and execution of local PowerShell scripts
to be permitted by your existing policy. It does not change the execution policy
or disable TLS verification. An unavailable public API causes a failure, not a
skipped or falsely successful test. This script creates only `test-output/`, which
is ignored by Git; generated files stay in the current checkout.

## Safety and cost boundaries

- Standard Windows runners only; no larger runners, cloud VM provisioning,
  schedules, remote desktop, third-party secrets, or authenticated API tests.
- Workflow permissions are `contents: read`; checkout credentials are not persisted.
- No artifact uploads. Version information, public responses, and assertions appear
  in workflow logs and the job summary.
- Standard GitHub-hosted runner execution is free for public repositories under
  [GitHub's current billing rules](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
- The hosted VM is discarded after the job; this repository and its run logs remain.
- Passing results do not establish compatibility with every Windows version,
  corporate proxy, certificate store, or older curl version.

## References

- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Workflow shell selection](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [curl manual](https://curl.se/docs/manpage.html)
- [JSONPlaceholder guide](https://jsonplaceholder.typicode.com/guide/)
