# DX Code Review Bot

Automated pull request review for DevriX WordPress plugins, themes, and Gutenberg work. It posts a structured review in English, focused on security, WordPress.com VIP safety, REST/AJAX authorization, and production performance.

A human reviewer still owns the merge decision. The bot exists to catch real defects early, not to replace review.

## What it does

On **push to a new feature branch**, the bot opens a **draft pull request** and reviews that. Comments go in Conversation, like a normal PR. GitHub has no review thread without a PR; a draft is the native place for them.

- Later WIP commits on that draft are left quiet (no comment spam).
- `@dx-review` or **Ready for review** starts another pass.
- If a PR already exists for the branch, this push job does nothing.

On each non-draft pull request (opened, updated, reopened, or marked ready), **DX Code Review Bot**:

1. Reads the PR diff through the GitHub API (it does not check out or run fork code).
2. Sends that diff to DeepSeek with a DevriX / WordPress VIP system prompt.
3. Posts a GitHub review **and** a Conversation comment, branded as DX Code Review Bot.
4. On **Request changes** (Blocker/High): converts the PR back to **draft** and fails the check (red).
5. If someone converts the PR to draft while a review is running, that run is **cancelled**.

Skip a run by putting `skip cr` in the PR **title**. Do not put that phrase in the description unless you really mean to skip.

Re-run on demand by commenting **`@dx-review`** on the PR (owners, members, and collaborators only).

## Verdicts

| Verdict | When |
| --- | --- |
| **Request changes** | Any Blocker or High finding (XSS, SQL injection, missing nonce/caps, VIP-unsafe filesystem, and similar). PR is converted to draft and the check goes red. |
| **Comment** | Medium findings only. Check stays green. |
| **Looks good** | Clean diff, or only nits. Check stays green. |

## Repository setup

### 1. Secrets

| Secret | Required | Purpose |
| --- | --- | --- |
| `DEEPSEEK_API_PR_REVIEW` | Yes | DeepSeek API key |
| `DX_REVIEW_GITHUB_TOKEN` | No | Token of a GitHub App or bot user named **DX Code Review Bot**. If unset, comments appear as `github-actions[bot]` with the DX header in the body. |

Add them under **Settings → Secrets and variables → Actions**.

Also enable **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests**. Without that, the bot cannot open the automatic draft PR (`GITHUB_TOKEN` is not allowed to create PRs). A PAT/GitHub App in `DX_REVIEW_GITHUB_TOKEN` is the alternative.

Prefer an organization secret so every DevriX repo inherits the same key.

### 2. This template repository

The workflow in this repo is the source of truth:

[`.github/workflows/dx-code-review.yml`](.github/workflows/dx-code-review.yml)

It already runs here. After you merge changes to `master`, new PRs use the updated prompt and branding.

### 3. Other DevriX repositories

Copy [`.github/workflows/dx-code-review.yml`](.github/workflows/dx-code-review.yml) into the plugin/theme repo and set `DEEPSEEK_API_PR_REVIEW`. The workflow pulls the prompt/scripts from `DevriX/automatic-pr-check@master`, so merge this bot there first.

### 4. Optional: comments as DX Code Review Bot

`GITHUB_TOKEN` always publishes as `github-actions[bot]`. To show the **DX Code Review Bot** name and avatar on the review:

1. Create a GitHub App (or machine user) named `DX Code Review Bot`.
2. Grant it **Pull requests: Read and write** and **Contents: Read** on the target repos.
3. Store the app installation token (or a fine-grained PAT) as `DX_REVIEW_GITHUB_TOKEN`.

Until that secret exists, the review body still opens with `# DX Code Review Bot`.

## Behaviour details

- **New branches:** the first push opens a draft PR and posts the review in Conversation. Further pushes to that draft are not re-reviewed until Ready for review or `@dx-review`.
- **Draft PRs** opened by a human are skipped until they are marked ready for review. Converting to draft cancels any in-flight review run.
- **Request changes** converts the PR to draft and fails the check. Mark **Ready for review** after the fix; that triggers a new review.
- **Dependabot / Renovate** PRs are skipped.
- A newer push cancels an in-flight review on the same PR (`concurrency`).
- Diffs larger than 100k Unicode width are skipped to cap API cost. Split the PR or comment `@dx-review` after shrinking it.
- Generated noise is ignored (`node_modules`, `vendor`, lockfiles, minified assets, maps, fonts, images).
- Model: `deepseek-flash`. Temperature: `0.2` for more consistent findings.

## Security notes

The pull-request job uses `pull_request_target` so it can post reviews on fork PRs and read repository secrets. That is safe only because:

- The workflow file is taken from the **base** branch, not from the PR.
- The review action fetches the diff over the API.
- There is **no** `actions/checkout` of the PR head, and no execution of PR scripts.

The **branch job** runs on `push` (collaborators only, not forks). It checks out that branch, opens a **draft PR**, and posts the review on it. Do not add a checkout of `github.event.pull_request.head.sha` to the pull-request job.

## Local test

Push a new branch (no PR yet) with an obvious WordPress security mistake. Confirm that:

1. A **draft PR** is opened automatically
2. A Conversation comment and review appear on that draft
3. Request changes keeps it draft and turns the check red

Put `skip cr` in the title if you need a PR that must not be reviewed. Never put that keyword in the PR body by accident (the bot treats it as a skip).
