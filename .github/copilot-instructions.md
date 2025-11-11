# Azure Lab Repository Guidelines

This file defines conventions and a small contract for labs in this repo. It is intended to be used by contributors and automated assistants (e.g., Copilot) to produce consistent, secure, and well-documented lab content.

## Directory layout (required)
Each lab should follow this layout:

labs/
  <service-name>/
    README.md
    infrastructure/
      main.bicep
      parameters.example.json
      parameters.json (optional, not checked in with secrets)
    scripts/
      deploy.sh
      cleanup.sh
      validate.sh
    tests/ (optional)
      smoke-test.sh

- Use lowercase with hyphens for folder and file names (e.g., `azure-vm-lab`).
- Keep Bicep templates in `infrastructure/` and helper scripts in `scripts/`.

## README requirements
Every lab README must include:
- Lab Overview (1–3 short paragraphs)
- Prerequisites (Azure CLI, roles, optional quotas)
- Deployment instructions with a one-liner and full command examples
- Validation steps and expected success criteria
- Cleanup instructions 


## Bicep & ARM templates
- Prefer Bicep (place in `infrastructure/main.bicep`).
- Keep `parameters.example.json` as the sanitized example.
- Add comments describing the purpose and major parameters.
- Export outputs for critical values (endpoints, IDs) using `output` declarations.

Naming examples:
- Resource groups: `rg-<service>-lab-<shortid>`
- Storage accounts: `st<shortunique>`

## Scripts
- Scripts must be idempotent (safe to rerun), have clear logs, and return non-zero on failure.
 - Scripts should target Bash/Linux. Document if any other script types are provided; the primary supported scripts must be Bash.

## Validation & tests
- Provide `scripts/validate.*` to verify resources and print PASS/FAIL.
- Optional: unit tests for helpers in `tests/`.

## Security & Secrets
- Never commit secrets. Use Key Vault or GitHub secrets for CI.
- Document which secrets are required (e.g., `AZURE_CLIENT_ID`, etc.).

## CI / PR Checklist (suggested)
- Validate Bicep: `az bicep build --file infrastructure/main.bicep`
- Run `scripts/validate.*` where possible (or a dry-run smoke check)
- Ensure `.env.example` exists and `.env` is listed in `.gitignore`.
- Run secret detection (e.g., `gitleaks detect --source .`) and fail the PR if secrets or `.env` files are committed.
- Confirm README includes required sections
- No secrets in PR (use pre-commit/gitleaks)

## Copilot behavior (authoring guidance)
- Follow repository conventions exactly when generating labs, templates, and scripts.
- Write concise, accurate README usage examples and one-liner deployment commands.
- Keep generated scripts idempotent and include validation and cleanup steps.
- Avoid including hard-coded secrets; use placeholders and clearly mark where secrets should be supplied.
- Prefer clear in-line comments explaining non-obvious steps.

### README Authoring: DO / AVOID
The first-time lab user should see only what they need to succeed. Keep historical context out of lab READMEs.

DO:
- Assume a fresh clone and user working directly inside `labs/<lab-name>/`.
- Provide: prerequisites, deployment, validation, cleanup, and minimal troubleshooting.
- Use copyable fenced code blocks (one command per line, no shell prompts).
- Keep tables compact (e.g., endpoint summaries) and avoid verbose prose.
- Reference current paths only; ensure examples match actual file locations.
- Explain environment file handling (`.env.example` vs `.env`) succinctly.

AVOID:
- Mentioning removed or deprecated directories (cleanup belongs in commit history, not README).
- Long migration stories or internal refactor notes.
- Repeating identical commands in multiple sections.
- Exposing implementation details better suited for `docs/` (architecture, deep design rationales).
- Adding warnings already mitigated (e.g., multiple lockfiles) unless user action is required.
- Embedding secrets or suggesting storing secrets in tracked files.
- Next Steps Optional Enhancements


When updating an existing README:
1. Re-run validation script and build to confirm examples still work.
2. Check for broken path aliases or imports after structural changes.
3. Keep troubleshooting list to the top 3–4 actionable problems.
4. Avoid adding historical cleanup statements—remove stale references entirely instead.



By following these rules contributors and automation will produce consistent, secure, and testable labs across this repository.
