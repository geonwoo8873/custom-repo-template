#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

warning() {
  echo "::warning::$1"
}

require_commandline() {
  local var_name="$1"
  if ! command -v "$var_name" &> /dev/null; then
    fail "Command line argument $var_name is required."
  fi
}

require_commandline jq
require_commandline curl

GITHUB_REQUIRED_ENVIRONMENT=(
  "GITHUB_TOKEN"
  "GITHUB_REPOSITORY"
  "GITHUB_EVENT_PATH"
  "GITHUB_API_URL"
)

for var in "${GITHUB_REQUIRED_ENVIRONMENT[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    fail "Environment variable $var is not set."
  fi
done

EVENT_PATH="${GITHUB_EVENT_PATH}"
API_URL="${GITHUB_API_URL:-https://api.github.com}"
REPOSITORY="${GITHUB_REPOSITORY}"

if [ ! -f "$EVENT_PATH" ]; then
  fail "GitHub event payload file does not exist: $EVENT_PATH"
fi

if [ -n "${GITHUB_API_URL:-}" ]; then
  warning "GITHUB_API_URL is set to: $API_URL"
else
  warning "GITHUB_API_URL is not set. Using default: $API_URL"
fi

PULL_REQUEST_NUMBER="$(jq -r '.pull_request.number // empty' "$EVENT_PATH")"
AUTHOR_LOGIN="$(jq -r '.pull_request.user.login // empty' "$EVENT_PATH")"
COMMIT_SHA="$(jq -r '.pull_request.head.sha // empty' "$EVENT_PATH")"
BRANCH_NAME="$(jq -r '.pull_request.head.ref // empty' "$EVENT_PATH")"

if [ -z "$PULL_REQUEST_NUMBER" ] || [ -z "$AUTHOR_LOGIN" ] || [ -z "$COMMIT_SHA" ] || [ -z "$BRANCH_NAME" ]; then
  fail "No pull_request payload found or required fields are missing."
fi

COMMITS_RESPONSE="$(
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/repos/$REPOSITORY/pulls/$PULL_REQUEST_NUMBER/commits"
)"

COMMIT_SHA_LIST="$(printf '%s' "$COMMITS_RESPONSE" | jq -r '.[].sha' | paste -sd '\n' -)"
if [ -z "$COMMIT_SHA_LIST" ]; then
  fail "Failed to load commit SHAs for the pull request."
fi

CHANGED_FILES_RESPONSE="$(
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/repos/$REPOSITORY/pulls/$PULL_REQUEST_NUMBER/files?per_page=100"
)"

DOC_ONLY=true
if [ -n "$CHANGED_FILES_RESPONSE" ] && [ "$CHANGED_FILES_RESPONSE" != "[]" ]; then
  while IFS= read -r file_name; do
    [ -n "$file_name" ] || continue
    case "$file_name" in
      *.md|*.mdx|*.markdown)
        ;;
      *)
        DOC_ONLY=false
        ;;
    esac
  done <<< "$(printf '%s' "$CHANGED_FILES_RESPONSE" | jq -r '.[].filename // empty')"
fi

BRANCH_NAME_LOWER="$(printf '%s' "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]')"
LABELS_TO_ADD=()

if [ "$DOC_ONLY" = true ]; then
  LABELS_TO_ADD+=("document")
else
  LABELS_TO_ADD+=("enhancement")
fi

case "$BRANCH_NAME_LOWER" in
  *refactor*) LABELS_TO_ADD+=("refactor") ;;
  *bug*|*fix*|*hotfix*|*bugfix*) LABELS_TO_ADD+=("bug") ;;
  *release*) LABELS_TO_ADD+=("release") ;;
esac

declare -A SEEN=()
FINAL_LABELS=()
for label in "${LABELS_TO_ADD[@]}"; do
  if [ -n "$label" ] && [ -z "${SEEN[$label]+x}" ]; then
    FINAL_LABELS+=("$label")
    SEEN["$label"]=1
  fi
done

ensure_label() {
  local label_name="$1"
  local label_color="$2"
  local exists

  exists="$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/repos/$REPOSITORY/labels/$label_name" 2>/dev/null || true)"

  if [ -z "$exists" ]; then
    curl -fsSL -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      "$API_URL/repos/$REPOSITORY/labels" \
      -d "$(jq -n --arg name "$label_name" --arg color "$label_color" '{name: $name, color: $color}')" >/dev/null 2>&1 || true
  fi
}

for label_name in "document" "enhancement" "refactor" "bug" "release"; do
  case "$label_name" in
    document) ensure_label "$label_name" "0075ca" ;;
    enhancement) ensure_label "$label_name" "a2eeef" ;;
    refactor) ensure_label "$label_name" "d4c5f9" ;;
    bug) ensure_label "$label_name" "d73a4a" ;;
    release) ensure_label "$label_name" "0e8a16" ;;
  esac
done

LABELS_JSON="$(printf '%s\n' "${FINAL_LABELS[@]}" | jq -R . | jq -s -c .)"

curl -fsSL -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  "$API_URL/repos/$REPOSITORY/issues/$PULL_REQUEST_NUMBER/labels" \
  -d "$(jq -n --argjson labels "$LABELS_JSON" '{labels: $labels}')" >/dev/null

USER_RESPONSE="$(
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL/users/$AUTHOR_LOGIN"
)"

if [ -z "$USER_RESPONSE" ]; then
  fail "Failed to fetch user information from GitHub API."
fi

AUTHOR_ID="$(jq -r '.id // empty' <<< "$USER_RESPONSE")"

if [ -z "$AUTHOR_ID" ]; then
  fail "Failed to extract author ID from GitHub API response."
fi

TEMPLATE_PATH=".github/PULL_REQUEST_TEMPLATE/pull_request_template.md"
if [ ! -f "$TEMPLATE_PATH" ]; then
  fail "PR template not found: $TEMPLATE_PATH"
fi

if [ ! -r "$TEMPLATE_PATH" ]; then
  fail "Pull request template is not readable: $TEMPLATE_PATH"
fi

PR_BODY="$(cat "$TEMPLATE_PATH")"
PR_BODY="${PR_BODY//__COMMIT_SHA__/$COMMIT_SHA_LIST}"

PAYLOAD="$(jq -n --arg body "$PR_BODY" '{body: $body}')"

curl -fsSL -X PATCH \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  "$API_URL/repos/$REPOSITORY/pulls/$PULL_REQUEST_NUMBER" \
  -d "$PAYLOAD" >/dev/null

echo "author=$AUTHOR_LOGIN, template='$TEMPLATE_PATH', branch=$BRANCH_NAME, commit_sha=$COMMIT_SHA_LIST, labels=${FINAL_LABELS[*]}"
