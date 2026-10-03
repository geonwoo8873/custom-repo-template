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

# PR 정보 요청에 필요한 GitHub 환경 변수를 Array 형태로 정의
GITHUB_REQUIRED_ENV=(
    "GITHUB_TOKEN" # 0
    "GITHUB_REPOSITORY" # 1 
    "GITHUB_EVENT_PATH" # 2
    "GITHUB_API_URL" # 3
)

# 필수 GitHub 환경 변수가 설정되어 있는지 확인
for env_var in "${GITHUB_REQUIRED_ENV[@]}"; do
  if [ -z "${!env_var:-}" ]; then
    fail "$env_var is required."
  fi
done

# PR 번호와 작성자 로그인 정보를 GitHub 이벤트 페이로드에서 추출
PR_NUMBER="$(jq -r '.pull_request.number // empty' "${!GITHUB_REQUIRED_ENV[2]}")"
AUTHOR_LOGIN="$(jq -r '.pull_request.user.login // empty' "${!GITHUB_REQUIRED_ENV[2]}")"

# GitHub 이벤트 페이로드 파일이 존재하는지 확인
if [ ! -f "${!GITHUB_REQUIRED_ENV[2]:-}" ]; then
    fail "GitHub event payload file does not exist: ${!GITHUB_REQUIRED_ENV[2]}"
fi

# GitHub API URL이 설정되어 있지 않으면 기본값으로 설정
if [ -z "${!GITHUB_REQUIRED_ENV[3]:-}" ]; then
  export "${!GITHUB_REQUIRED_ENV[3]}"="https://api.github.com"
fi

# PR 번호와 작성자 로그인 정보가 올바르게 추출되었는지 확인
if [ -z "$PR_NUMBER" ] || [ -z "$AUTHOR_LOGIN" ]; then
  fail "No pull_request payload found or required fields are missing."
fi

# 작성자 정보를 GitHub API를 통해 조회
USER_RESPONSE="$(

  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${!GITHUB_REQUIRED_ENV[0]}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${!GITHUB_REQUIRED_ENV[3]}/users/$AUTHOR_LOGIN"
)"

USER_RESPONSE="$(
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${!GITHUB_REQUIRED_ENV[0]}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${!GITHUB_REQUIRED_ENV[3]}/users/$AUTHOR_LOGIN"
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
  -H "Authorization: Bearer ${!GITHUB_REQUIRED_ENV[0]}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  "${!GITHUB_REQUIRED_ENV[3]}/repos/${!GITHUB_REQUIRED_ENV[1]}/pulls/$PR_NUMBER" \
  -d "$PAYLOAD" >/dev/null

echo "author=$AUTHOR_LOGIN, location='$LOCATION', locale=$LOCALE, template='$TEMPLATE_PATH'"