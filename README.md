# DX Code Review Bot

Automated pull request review for DevriX WordPress plugins, themes, and Gutenberg work. It posts a structured review in English, focused on security, WordPress.com VIP safety, REST/AJAX authorization, and production performance.

A human reviewer still owns the merge decision. The bot exists to catch real defects early, not to replace review.

## What it does

On each non-draft pull request (opened, updated, reopened, or marked ready), **DX Code Review Bot**:

1. Reads the PR diff through the GitHub API (it does not check out or run fork code).
2. Sends that diff to DeepSeek with a DevriX / WordPress VIP system prompt.
3. Posts one review on the PR, branded as DX Code Review Bot, with a verdict and severity-ranked findings.

Skip a run by putting `skip review` or `skip cr` in the PR title or body.

Re-run on demand by commenting **`@dx-review`** on the PR (owners, members, and collaborators only).

## Verdicts

| Verdict | When |
| --- | --- |
| **Request changes** | Any Blocker or High finding (XSS, SQL injection, missing nonce/caps, VIP-unsafe filesystem, and similar) |
| **Comment** | Medium findings only |
| **Looks good** | Clean diff, or only nits |

The GitHub check still **passes** after a review is posted. A red finding is a review comment, not a failed CI job. That is intentional: the bot must not silently block merge the way a test suite does.

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
  pull_request_target:
    types: [opened, reopened, synchronize, ready_for_review]
  issue_comment:
    types: [created]

permissions:
  contents: read
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

- **Draft PRs** are skipped until they are marked ready for review. `@dx-review` still works on drafts.
- **Dependabot / Renovate** PRs are skipped.
- A newer push cancels an in-flight review on the same PR (`concurrency`).
- Diffs larger than 100k Unicode width are skipped to cap API cost. Split the PR or comment `@dx-review` after shrinking it.
- Generated noise is ignored (`node_modules`, `vendor`, lockfiles, minified assets, maps, fonts, images).
- Model: `deepseek-flash`. Temperature: `0.2` for more consistent findings.

## Security notes

This workflow uses `pull_request_target` so it can post reviews on fork PRs and read repository secrets. That is safe only because:

- The workflow file is taken from the **base** branch, not from the PR.
- The review action fetches the diff over the API.
- There is **no** `actions/checkout` of the PR head, and no execution of PR scripts.

Do not add a checkout of `github.event.pull_request.head.sha` to this job.

## Local test

Open a PR against `master` in this repo with an obvious WordPress security mistake. Confirm that:

1. The **DX Code Review Bot** workflow starts.
2. A review appears on the PR with Blocker/High findings and a **Request changes** verdict.

Put `skip review` in the title if you need a PR that must not be reviewed.
