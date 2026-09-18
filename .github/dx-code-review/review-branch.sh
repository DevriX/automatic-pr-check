#!/usr/bin/env bash
# Open a draft PR for a new feature branch and post the review there.
# GitHub cannot attach PR comments without a PR; a draft PR is the native place.
# Required env: DEEPSEEK_API_KEY, GH_TOKEN, REPO, SHA, BRANCH, DEFAULT_BRANCH, PROMPT_FILE
set -euo pipefail

MAX_LENGTH="${MAX_LENGTH:-100000}"
MARKER='<!-- dx-code-review-bot -->'
AUTO_PR_MARKER='<!-- dx-auto-draft-pr -->'

post_check() {
  local conclusion="$1"
  local title="$2"
  local summary="$3"
  jq -n \
    --arg sha "$SHA" \
    --arg conclusion "$conclusion" \
    --arg title "$title" \
    --arg summary "$summary" \
    '{
      name: "DX Code Review Bot",
      head_sha: $sha,
      status: "completed",
      conclusion: $conclusion,
      output: {title: $title, summary: $summary}
    }' | gh api -X POST "repos/${REPO}/check-runs" --input - >/dev/null
}

skip_check() {
  echo "Skipping branch review: $1"
  post_check "neutral" "Skipped" "$1"
  exit 0
}

post_or_update_comment() {
  local pr_number="$1"
  local body="$2"
  local comment_id
  comment_id="$(
    gh api "repos/${REPO}/issues/${pr_number}/comments" --paginate \
      --jq ".[] | select(.body | contains(\"${MARKER}\")) | .id" \
      | tail -n1 || true
  )"
  if [ -n "$comment_id" ]; then
    jq -n --arg body "$body" '{body: $body}' \
      | gh api -X PATCH "repos/${REPO}/issues/comments/${comment_id}" --input - >/dev/null
  else
    jq -n --arg body "$body" '{body: $body}' \
      | gh api -X POST "repos/${REPO}/issues/${pr_number}/comments" --input - >/dev/null
  fi
}

parse_verdict() {
  local text="$1"
  if printf '%s' "$text" | grep -qiE 'DX_VERDICT:[[:space:]]*REQUEST_CHANGES'; then
    echo "REQUEST_CHANGES"
  elif printf '%s' "$text" | grep -qiE 'DX_VERDICT:[[:space:]]*LOOKS_GOOD'; then
    echo "LOOKS_GOOD"
  elif printf '%s' "$text" | grep -qiE 'DX_VERDICT:[[:space:]]*COMMENT'; then
    echo "COMMENT"
  elif printf '%s' "$text" | grep -qiE 'Request changes|Do not merge|### \[BLOCKER\]'; then
    echo "REQUEST_CHANGES"
  elif printf '%s' "$text" | grep -qiE 'Looks good'; then
    echo "LOOKS_GOOD"
  else
    echo "COMMENT"
  fi
}

subject="$(git log -1 --format=%s "${SHA}")"
if printf '%s' "$subject" | grep -qiE 'skip cr|skip review'; then
  skip_check "Latest commit subject requested a skip."
fi

open_pr="$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')"
if [ -n "$open_pr" ]; then
  skip_check "Open PR #${open_pr} already exists for ${BRANCH}; later pushes to a draft are left quiet until Ready for review or @dx-review."
fi

git fetch --no-tags origin "${DEFAULT_BRANCH}:refs/remotes/origin/${DEFAULT_BRANCH}"

diff="$(
  git diff "origin/${DEFAULT_BRANCH}...${SHA}" -- \
    ':(exclude)node_modules/**' \
    ':(exclude)vendor/**' \
    ':(exclude)build/**' \
    ':(exclude)dist/**' \
    ':(exclude)coverage/**' \
    ':(exclude)*.min.js' \
    ':(exclude)*.min.css' \
    ':(exclude)package-lock.json' \
    ':(exclude)pnpm-lock.yaml' \
    ':(exclude)yarn.lock' \
    ':(exclude)composer.lock' \
    ':(exclude)*.map' \
    ':(exclude)*.svg' \
    ':(exclude)*.woff' \
    ':(exclude)*.woff2' \
    ':(exclude)*.ttf' \
    ':(exclude)*.eot' \
    ':(exclude)*.png' \
    ':(exclude)*.jpg' \
    ':(exclude)*.jpeg' \
    ':(exclude)*.gif' \
    ':(exclude)*.webp' \
    ':(exclude)*.ico' \
    ':(exclude)*.pdf' \
    ':(exclude)*.zip' \
    ':(exclude)*.mo' \
    ':(exclude)*.pot'
)"

if [ -z "$diff" ]; then
  skip_check "No reviewable diff against ${DEFAULT_BRANCH}."
fi

if [ "${#diff}" -gt "$MAX_LENGTH" ]; then
  skip_check "Diff is ${#diff} characters (limit ${MAX_LENGTH}). Split the branch."
fi

title="$subject"
if [ -z "$title" ] || [ ${#title} -gt 90 ]; then
  title="WIP: ${BRANCH}"
fi
title="${title//$'\r'/}"

pr_body="$(cat <<EOF
${AUTO_PR_MARKER}
${MARKER}

## DX Code Review Bot

Opened automatically as a **draft** when \`${BRANCH}\` was pushed, so review comments can live on the pull request (not on a commit).

- Later WIP pushes to this draft are **not** re-reviewed.
- Comment \`@dx-review\` for another pass, or mark **Ready for review** when a human should look.
EOF
)"

if ! pr_url="$(
  gh pr create \
    --repo "${REPO}" \
    --base "${DEFAULT_BRANCH}" \
    --head "${BRANCH}" \
    --draft \
    --title "${title}" \
    --body "${pr_body}"
)"; then
  echo "Could not open a draft PR. In the repository: Settings → Actions → General → Workflow permissions → enable \"Allow GitHub Actions to create and approve pull requests\". Or set DX_REVIEW_GITHUB_TOKEN to a PAT/GitHub App token that can open pull requests."
  exit 1
fi

pr_number="$(printf '%s' "$pr_url" | grep -oE '[0-9]+$')"
echo "Opened draft PR #${pr_number}: ${pr_url}"

user_prompt="$(cat <<EOF
Review this GitHub Pull Request diff as DX Code Review Bot.
The PR is a draft opened automatically from a feature branch. Follow the required output format exactly.
Comment only on issues you can justify from the changed lines.
If there are no justified findings, use a Looks good verdict. End with the DX_VERDICT line.

${diff}
EOF
)"

jq -n \
  --rawfile sys "${PROMPT_FILE}" \
  --arg user "$user_prompt" \
  '{
    model: "deepseek-flash",
    temperature: 0.2,
    messages: [
      {role: "system", content: $sys},
      {role: "user", content: $user}
    ]
  }' > /tmp/dx-review-payload.json

api_response="$(
  curl -sS https://api.deepseek.com/chat/completions \
    -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/dx-review-payload.json
)"

if ! printf '%s' "$api_response" | jq -e '.choices[0].message.content' >/dev/null; then
  echo "DeepSeek API error:"
  echo "$api_response"
  exit 1
fi

body="$(printf '%s' "$api_response" | jq -r '.choices[0].message.content')"
verdict="$(parse_verdict "$body")"
summary="$(printf '%s' "$body" | head -c 65000)"

if [ "$verdict" = "REQUEST_CHANGES" ]; then
  conclusion="failure"
  check_title="Request changes"
elif [ "$verdict" = "LOOKS_GOOD" ]; then
  conclusion="success"
  check_title="Looks good"
else
  conclusion="neutral"
  check_title="Comment"
fi

post_check "$conclusion" "$check_title" "$summary"

jq -n --arg body "$body" --arg sha "$SHA" '{commit_id: $sha, body: $body, event: "COMMENT"}' \
  | gh api -X POST "repos/${REPO}/pulls/${pr_number}/reviews" --input - >/dev/null

comment="${MARKER}
## DX Code Review Bot

**Verdict:** \`${verdict}\`

This pull request was opened as a **draft** so findings appear in Conversation.

"

if [ "$verdict" = "REQUEST_CHANGES" ]; then
  comment="${comment}Blocker/High issues were found. Keep it draft until they are fixed, then comment \`@dx-review\` or mark **Ready for review**.
"
elif [ "$verdict" = "LOOKS_GOOD" ]; then
  comment="${comment}No Blocker/High issues from this diff. Mark **Ready for review** when a human should take it.
"
else
  comment="${comment}Medium findings only. A human reviewer should still confirm before merge.
"
fi

post_or_update_comment "$pr_number" "$comment"

echo "Draft PR #${pr_number} verdict: ${verdict}"
if [ "$verdict" = "REQUEST_CHANGES" ]; then
  exit 1
fi
