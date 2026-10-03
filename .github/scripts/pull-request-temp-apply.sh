#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

warn() {
  echo "::warning::$1"
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Required command not found: $command_name"
  fi
}

require_command jq
require_command curl

if [ -z "${GITHUB_TOKEN:-}" ]; then
  fail "GITHUB_TOKEN is required."
fi

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  fail "GITHUB_REPOSITORY is required."
fi

if [ -z "${GITHUB_EVENT_PATH:-}" ]; then
  fail "GITHUB_EVENT_PATH is required."
fi

if [ ! -f "$GITHUB_EVENT_PATH" ]; then
  fail "GitHub event payload file does not exist: $GITHUB_EVENT_PATH"
fi

if [ -z "${GITHUB_API_URL:-}" ]; then
  GITHUB_API_URL="https://api.github.com"
fi

PR_NUMBER="$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")"
AUTHOR_LOGIN="$(jq -r '.pull_request.user.login // empty' "$GITHUB_EVENT_PATH")"

if [ -z "$PR_NUMBER" ] || [ -z "$AUTHOR_LOGIN" ]; then
  fail "No pull_request payload found or required fields are missing."
fi

USER_RESPONSE="$(
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$GITHUB_API_URL/users/$AUTHOR_LOGIN"
)"

LOCATION="$(printf '%s' "$USER_RESPONSE" | jq -r '.location // ""' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
LOCATION_LOWER="$(printf '%s' "$LOCATION" | tr '[:upper:]' '[:lower:]')"

LOCALE="en"
if printf '%s' "$LOCATION_LOWER" | grep -Eq 'south korea|republic of korea' || printf '%s' "$LOCATION" | grep -Eq '대한민국|한국'; then
  LOCALE="ko"
fi

TEMPLATE_DIR=".github/PULL_REQUEST_TEMPLATE"
if [ ! -d "$TEMPLATE_DIR" ]; then
  fail "Template directory not found: $TEMPLATE_DIR"
fi

pick_template_by_locale() {
  local target_locale="$1"
  shopt -s nullglob
  local candidates=("$TEMPLATE_DIR"/*."$target_locale".md)
  shopt -u nullglob

  if [ "${#candidates[@]}" -eq 0 ]; then
    return 1
  fi

  printf '%s\n' "${candidates[@]}" | sort -f | head -n 1
}

if [ "$LOCALE" = "ko" ]; then
  TEMPLATE_PATH="$(
    pick_template_by_locale "ko" \
    || pick_template_by_locale "kr" \
    || true
  )"
else
  TEMPLATE_PATH="$(pick_template_by_locale "en" || true)"
fi

if [ -z "$TEMPLATE_PATH" ]; then
  warn "No .$LOCALE.md template found. Falling back to .en.md."
  TEMPLATE_PATH="$(pick_template_by_locale "en" || true)"
fi

if [ -z "$TEMPLATE_PATH" ]; then
  fail "No PR template found. Expected at least one .en.md file in .github/PULL_REQUEST_TEMPLATE."
fi

if [ ! -r "$TEMPLATE_PATH" ]; then
  fail "Pull request template is not readable: $TEMPLATE_PATH"
fi

PR_BODY="$(cat "$TEMPLATE_PATH")"

PAYLOAD="$(jq -n --arg body "$PR_BODY" '{body: $body}')"

curl -fsSL -X PATCH \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" \
  -d "$PAYLOAD" >/dev/null

echo "author=$AUTHOR_LOGIN, location='$LOCATION', locale=$LOCALE, template='$TEMPLATE_PATH'"