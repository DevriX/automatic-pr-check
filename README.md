# DX Code Review Bot

Automated pull request review for DevriX WordPress plugins, themes, and Gutenberg work. It posts a structured review in English, focused on security, WordPress.com VIP safety, REST/AJAX authorization, and production performance.

A human reviewer still owns the merge decision. The bot exists to catch real defects early, not to replace review.

## What it does

On **push to a feature branch** (before a PR exists), the bot:

1. Diffs the branch against the default branch.
2. Posts a **commit comment** if there are findings (GitHub cannot attach a PR review without a PR).
3. Publishes a **DX Code Review Bot** check on the commit. Request changes makes the check red.

If an open PR already exists for that branch, the pre-PR job is skipped so you do not get two reviews.

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

Prefer an organization secret so every DevriX repo inherits the same key.

### 2. This template repository

The workflow in this repo is the source of truth:

[`.github/workflows/dx-code-review.yml`](.github/workflows/dx-code-review.yml)

It already runs here. After you merge changes to `master`, new PRs use the updated prompt and branding.

### 3. Other DevriX repositories (recommended)

Keep one copy of the logic. From the plugin/theme repo, add `.github/workflows/dx-code-review.yml`:

```yaml
name: DX Code Review Bot

on:
  push:
    branches-ignore: [master, main]
  pull_request_target:
    types: [opened, reopened, synchronize, ready_for_review, converted_to_draft]
  issue_comment:
    types: [created]

permissions:
  actions: write
  checks: write
  contents: write
  pull-requests: write

jobs:
  dx-code-review:
    uses: DevriX/automatic-pr-check/.github/workflows/dx-code-review.yml@master
    secrets:
      DEEPSEEK_API_PR_REVIEW: ${{ secrets.DEEPSEEK_API_PR_REVIEW }}
      DX_REVIEW_GITHUB_TOKEN: ${{ secrets.DX_REVIEW_GITHUB_TOKEN }}
```

Pin `@master` only while the bot is still moving quickly. For production plugins, pin a commit SHA of this repository instead.

### 4. Optional: comments as DX Code Review Bot

`GITHUB_TOKEN` always publishes as `github-actions[bot]`. To show the **DX Code Review Bot** name and avatar on the review:

1. Create a GitHub App (or machine user) named `DX Code Review Bot`.
2. Grant it **Pull requests: Read and write** and **Contents: Read** on the target repos.
3. Store the app installation token (or a fine-grained PAT) as `DX_REVIEW_GITHUB_TOKEN`.

Until that secret exists, the review body still opens with `# DX Code Review Bot`.

## Behaviour details

- **Pre-PR branches:** a push with no open PR gets a commit comment (only if there is a problem) and a check on the commit. Open the commit from the branch page to read it.
- **Draft PRs** are skipped until they are marked ready for review. Converting to draft cancels any in-flight review run. `@dx-review` still works on drafts.
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

The **pre-PR branch job** runs on `push` in the same repository (collaborators only, not forks). It checks out that branch to compute `git diff` against the default branch. Do not add a checkout of `github.event.pull_request.head.sha` to the pull-request job.

## Local test

Open a PR against `master` in this repo with an obvious WordPress security mistake. Confirm that:

1. The **DX Code Review Bot** workflow starts.
2. A review appears on the PR with Blocker/High findings and a **Request changes** verdict.

Put `skip cr` in the title if you need a PR that must not be reviewed. Never put that keyword in the PR body by accident (the bot treats it as a skip).
