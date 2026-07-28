#!/usr/bin/env bash
set -euo pipefail

base_url="${APP_BASE_URL:-http://localhost:8090}"
cookie_jar="$(mktemp)"
signup_html="$(mktemp)"
app_html="$(mktemp)"
check_email_html="$(mktemp)"
members_html="$(mktemp)"
billing_html="$(mktemp)"
invitation_html="$(mktemp)"
member_cookie_jar="$(mktemp)"
member_signup_html="$(mktemp)"
trap 'rm -f "$cookie_jar" "$signup_html" "$app_html" "$check_email_html" "$members_html" "$billing_html" "$invitation_html" "$member_cookie_jar" "$member_signup_html"' EXIT

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

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/check-email" > "$check_email_html"
verification_path="$(sed -n 's/.*data-development-verification href="\([^"]*\)".*/\1/p' "$check_email_html" | head -1)"
test -n "$verification_path"
verify_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    "$base_url$verification_path"
)"
test "$verify_status" = "200"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
grep --quiet "CI Workspace" "$app_html"
grep --quiet "owner" "$app_html"
grep --quiet "data-column-id=" "$app_html"
grep --quiet "data-card-id=" "$app_html"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/billing" > "$billing_html"
grep --quiet "Plan and billing" "$billing_html"
grep --quiet "Premium checkout will be available after Stripe is configured." "$billing_html"

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

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/members" > "$members_html"
invite_csrf_token="$(
  sed -n '/action="\/app\/members\/invite"/,/<\/form>/ s/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    "$members_html" | head -1
)"
invite_email="member-${run_id}-${GITHUB_RUN_ATTEMPT:-1}@example.test"
test -n "$invite_csrf_token"

invite_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/members/invite" \
    --data-urlencode "csrfToken=$invite_csrf_token" \
    --data-urlencode "email=$invite_email" \
    --data-urlencode "role=member"
)"
test "$invite_status" = "302"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/members" > "$members_html"
invitation_path="$(sed -n 's/.*class="development-invite-link" href="\([^"]*\)".*/\1/p' "$members_html" | head -1)"
test -n "$invitation_path"

curl --fail --silent --show-error --cookie-jar "$member_cookie_jar" \
  "$base_url$invitation_path" > "$invitation_html"
member_signup_path="$(sed -n 's/.*href="\([^"]*\/signup?invitationToken=[^"]*\)".*/\1/p' "$invitation_html" | head -1)"
test -n "$member_signup_path"

curl --fail --silent --show-error --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
  "$base_url$member_signup_path" > "$member_signup_html"
member_csrf_token="$(sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' "$member_signup_html" | head -1)"
invitation_token="$(sed -n 's/.*name="invitationToken" value="\([^"]*\)".*/\1/p' "$member_signup_html" | head -1)"
test -n "$member_csrf_token"
test -n "$invitation_token"

member_register_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
    --request POST "$base_url/auth/register" \
    --data-urlencode "csrfToken=$member_csrf_token" \
    --data-urlencode "invitationToken=$invitation_token" \
    --data-urlencode "displayName=CI Member" \
    --data-urlencode "email=$invite_email" \
    --data-urlencode "password=CI-member-password-2026"
)"
test "$member_register_status" = "302"

curl --fail --silent --show-error --cookie "$member_cookie_jar" "$base_url/check-email" > "$check_email_html"
member_verification_path="$(sed -n 's/.*data-development-verification href="\([^"]*\)".*/\1/p' "$check_email_html" | head -1)"
test -n "$member_verification_path"
curl --fail --silent --show-error --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
  "$base_url$member_verification_path" > /dev/null
curl --fail --silent --show-error --cookie "$member_cookie_jar" "$base_url/app" > "$app_html"
grep --quiet "CI Workspace" "$app_html"
grep --quiet "member" "$app_html"

echo "Functional smoke test passed"
