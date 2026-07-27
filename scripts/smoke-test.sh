#!/usr/bin/env bash
set -euo pipefail

base_url="${APP_BASE_URL:-http://localhost:8090}"
cookie_jar="$(mktemp)"
signup_html="$(mktemp)"
app_html="$(mktemp)"
trap 'rm -f "$cookie_jar" "$signup_html" "$app_html"' EXIT

curl --fail --silent --show-error --cookie-jar "$cookie_jar" "$base_url/signup" > "$signup_html"
csrf_token="$(sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' "$signup_html" | head -1)"
run_id="${GITHUB_RUN_ID:-local-$(date +%s)-$$}"
test_email="ci-${run_id}-${GITHUB_RUN_ATTEMPT:-1}@example.test"

test -n "$csrf_token"

register_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/auth/register" \
    --data-urlencode "csrfToken=$csrf_token" \
    --data-urlencode "displayName=CI Owner" \
    --data-urlencode "email=$test_email" \
    --data-urlencode "workspaceName=CI Workspace" \
    --data-urlencode "password=CI-secure-password-2026"
)"
test "$register_status" = "302"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
grep --quiet "CI Workspace" "$app_html"
grep --quiet "owner" "$app_html"
grep --quiet "data-column-id=" "$app_html"
grep --quiet "data-card-id=" "$app_html"

csrf_token="$(sed -n 's/.*data-csrf-token="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
column_id="$(grep -o 'data-column-id="[^"]*"' "$app_html" | head -1 | cut -d'"' -f2)"
test -n "$csrf_token"
test -n "$column_id"

create_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards" \
    --data-urlencode "csrfToken=$csrf_token" \
    --data-urlencode "columnId=$column_id" \
    --data-urlencode "title=CI live card" \
    --data-urlencode "description=Created by the CI smoke test"
)"
test "$create_status" = "302"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
grep --quiet "CI live card" "$app_html"

echo "Functional smoke test passed"
