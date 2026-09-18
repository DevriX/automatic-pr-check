#!/usr/bin/env bash
# Pre-PR branch review for DX Code Review Bot.
# Required env: DEEPSEEK_API_KEY, GH_TOKEN, REPO, SHA, BRANCH, DEFAULT_BRANCH, PROMPT_FILE
set -euo pipefail

MAX_LENGTH="${MAX_LENGTH:-100000}"
MARKER='<!-- dx-code-review-bot -->'

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
  echo "Skipping pre-PR review: $1"
  post_check "neutral" "Skipped" "$1"
  exit 0
}

subject="$(git log -1 --format=%s "${SHA}")"
if printf '%s' "$subject" | grep -qiE 'skip cr|skip review'; then
  skip_check "Latest commit subject requested a skip."
fi

open_pr="$(gh pr list --repo "${REPO}" --head "${BRANCH}" --state open --json number --jq '.[0].number // empty')"
if [ -n "$open_pr" ]; then
  skip_check "Open PR #${open_pr} already exists for ${BRANCH}; the pull-request review will handle comments."
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
  skip_check "Diff is ${#diff} characters (limit ${MAX_LENGTH}). Split the branch or open a smaller PR."
fi

user_prompt="$(cat <<EOF
Review this feature-branch diff as DX Code Review Bot. There is no Pull Request yet.
Follow the required output format exactly. Comment only on issues you can justify from the changed lines.
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

verdict="COMMENT"
if printf '%s' "$body" | grep -qiE 'DX_VERDICT:[[:space:]]*REQUEST_CHANGES'; then
  verdict="REQUEST_CHANGES"
elif printf '%s' "$body" | grep -qiE 'DX_VERDICT:[[:space:]]*LOOKS_GOOD'; then
  verdict="LOOKS_GOOD"
elif printf '%s' "$body" | grep -qiE 'DX_VERDICT:[[:space:]]*COMMENT'; then
  verdict="COMMENT"
elif printf '%s' "$body" | grep -qiE 'Request changes|Do not merge|### \[BLOCKER\]'; then
  verdict="REQUEST_CHANGES"
elif printf '%s' "$body" | grep -qiE 'Looks good'; then
  verdict="LOOKS_GOOD"
fi

summary="$(printf '%s' "$body" | head -c 65000)"
if [ "$verdict" = "REQUEST_CHANGES" ]; then
  conclusion="failure"
  title="Request changes"
elif [ "$verdict" = "LOOKS_GOOD" ]; then
  conclusion="success"
  title="Looks good"
else
  conclusion="neutral"
  title="Comment"
fi

post_check "$conclusion" "$title" "$summary"

if [ "$verdict" != "LOOKS_GOOD" ]; then
  comment="${MARKER}
## DX Code Review Bot (pre-PR)

**Branch:** \`${BRANCH}\`
**Verdict:** \`${verdict}\`

${body}

---
Open a pull request after the findings are addressed. This comment is on the commit because there is no PR yet.
"
  jq -n --arg body "$comment" '{body: $body}' \
    | gh api -X POST "repos/${REPO}/commits/${SHA}/comments" --input - >/dev/null
  echo "Posted a commit comment on ${SHA}."
fi

echo "Pre-PR verdict: ${verdict}"
if [ "$verdict" = "REQUEST_CHANGES" ]; then
  exit 1
fi
