#!/usr/bin/env bash
set -euo pipefail

base_url="${APP_BASE_URL:-http://localhost:8090}"
cookie_jar="$(mktemp)"
signup_html="$(mktemp)"
app_html="$(mktemp)"
check_email_html="$(mktemp)"
members_html="$(mktemp)"
billing_html="$(mktemp)"
profile_html="$(mktemp)"
partial_html="$(mktemp)"
history_restore_html="$(mktemp)"
invitation_html="$(mktemp)"
member_cookie_jar="$(mktemp)"
member_signup_html="$(mktemp)"
trap 'rm -f "$cookie_jar" "$signup_html" "$app_html" "$check_email_html" "$members_html" "$billing_html" "$profile_html" "$partial_html" "$history_restore_html" "$invitation_html" "$member_cookie_jar" "$member_signup_html"' EXIT

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
grep --quiet "Owner" "$app_html"
grep --quiet "data-column-id=" "$app_html"
grep --quiet "data-card-id=" "$app_html"
grep --quiet "data-workspace-menu-toggle" "$app_html"
grep --quiet '<!doctype html>' "$app_html"
grep --quiet 'class="workspace-sidebar"' "$app_html"

for partial_path in app app/members app/profile app/billing; do
  curl --fail --silent --show-error --cookie "$cookie_jar" \
    --header "HX-Request: true" "$base_url/$partial_path" > "$partial_html"
  grep --quiet 'id="workspace-main"' "$partial_html"
  if grep --quiet '<!doctype html>' "$partial_html"; then
    echo "HTMX response unexpectedly included the full document for /$partial_path" >&2
    exit 1
  fi
  if grep --quiet 'class="workspace-sidebar"' "$partial_html"; then
    echo "HTMX response unexpectedly included the shared sidebar for /$partial_path" >&2
    exit 1
  fi
done

curl --fail --silent --show-error --cookie "$cookie_jar" \
  --header "HX-Request: true" --header "HX-History-Restore-Request: true" \
  "$base_url/app" > "$history_restore_html"
grep --quiet '<!doctype html>' "$history_restore_html"
grep --quiet 'class="workspace-sidebar"' "$history_restore_html"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/billing" > "$billing_html"
grep --quiet "Plan and billing" "$billing_html"
curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/billing/status" \
  | grep --quiet '"plan":"free"'
curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/profile" > "$profile_html"
grep --quiet "Your profile" "$profile_html"
grep --quiet "Workspace plan" "$profile_html"
grep --quiet "My work" "$profile_html"
grep --quiet "Automations" "$profile_html"
grep --quiet "data-workspace-menu-close" "$profile_html"
profile_csrf="$(
  sed -n '/action="\/app\/profile\/details"/,/<\/form>/p' "$profile_html" \
    | sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    | head -1
)"
password_csrf="$(
  sed -n '/action="\/app\/profile\/password"/,/<\/form>/p' "$profile_html" \
    | sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    | head -1
)"
test -n "$profile_csrf"
test -n "$password_csrf"
profile_update_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/details" \
    --data-urlencode "csrfToken=$profile_csrf" \
    --data-urlencode "displayName=CI Owner Updated" \
    --data-urlencode "email=$test_email" \
    --data-urlencode "locale=en_US"
)"
test "$profile_update_status" = "302"
password_update_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/password" \
    --data-urlencode "csrfToken=$password_csrf" \
    --data-urlencode "currentPassword=CI-secure-password-2026" \
    --data-urlencode "newPassword=CI-updated-password-2026" \
    --data-urlencode "confirmPassword=CI-updated-password-2026"
)"
test "$password_update_status" = "302"

csrf_token="$(sed -n 's/.*data-csrf-token="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
column_id="$(grep -o 'data-column-id="[^"]*"' "$app_html" | head -1 | cut -d'"' -f2)"
target_column_id="$(grep -o 'data-column-id="[^"]*"' "$app_html" | sed -n '2p' | cut -d'"' -f2)"
card_id="$(grep -o 'data-card-id="[^"]*"' "$app_html" | head -1 | cut -d'"' -f2)"
test -n "$csrf_token"
test -n "$column_id"
test -n "$target_column_id"
test -n "$card_id"

move_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$card_id/move" \
    --data-urlencode "csrfToken=$csrf_token" \
    --data-urlencode "columnId=$target_column_id"
)"
printf '%s' "$move_response" | grep --quiet '"success":true'

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
