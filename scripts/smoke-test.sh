#!/usr/bin/env bash
set -euo pipefail
trap 'status=$?; echo "Functional smoke test failed near line ${LINENO}" >&2; exit "$status"' ERR

base_url="${APP_BASE_URL:-http://localhost:8090}"
cookie_jar="$(mktemp)"
signup_html="$(mktemp)"
app_html="$(mktemp)"
check_email_html="$(mktemp)"
members_html="$(mktemp)"
billing_html="$(mktemp)"
profile_html="$(mktemp)"
card_html="$(mktemp)"
partial_html="$(mktemp)"
history_restore_html="$(mktemp)"
invitation_html="$(mktemp)"
member_cookie_jar="$(mktemp)"
member_signup_html="$(mktemp)"
attachment_payload="$(mktemp)"
attachment_download="$(mktemp)"
trap 'rm -f "$cookie_jar" "$signup_html" "$app_html" "$check_email_html" "$members_html" "$billing_html" "$profile_html" "$card_html" "$partial_html" "$history_restore_html" "$invitation_html" "$member_cookie_jar" "$member_signup_html" "$attachment_payload" "$attachment_download"' EXIT

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
grep --quiet "data-wip-count" "$app_html"
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
if ! printf '%s' "$move_response" | grep --quiet -E '"(success|SUCCESS)"[[:space:]]*:[[:space:]]*true'; then
  echo "Unexpected card movement response: $move_response" >&2
  exit 1
fi

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
managed_card_id="$(grep --before-context=1 "CI live card" "$app_html" | grep -o 'data-card-id="[^"]*"' | tail -1 | cut -d'"' -f2)"
test -n "$managed_card_id"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$managed_card_id" > "$card_html"
grep --quiet "Card details" "$card_html"
card_csrf_token="$(sed -n 's/.*data-card-csrf-token="\([^"]*\)".*/\1/p' "$card_html" | head -1)"
test -n "$card_csrf_token"

card_update_result="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id" \
    --data-urlencode "csrfToken=$card_csrf_token" \
    --data-urlencode "title=CI managed card" \
    --data-urlencode "description=Updated through card management" \
    --data-urlencode "priority=high" \
    --data-urlencode "assigneeId=" \
    --data-urlencode "dueDate=2026-12-31" \
    --data-urlencode "labels=ci, regression"
)"
if [[ "$card_update_result" != 302*"updated=1" ]]; then
  echo "Unexpected card update redirect: $card_update_result" >&2
  exit 1
fi

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$managed_card_id?updated=1" > "$card_html"
if ! grep --quiet "CI managed card" "$card_html"; then
  echo "Updated card title was not rendered" >&2
  grep 'name="title"' "$card_html" >&2 || true
  exit 1
fi
grep --quiet "Updated through card management" "$card_html"
grep --quiet 'value="ci,regression"' "$card_html"
grep --quiet "updated the card" "$card_html"

card_comment_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id/comments" \
    --data-urlencode "csrfToken=$card_csrf_token" \
    --data-urlencode "body=CI management comment"
)"
test "$card_comment_status" = "302"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$managed_card_id?commented=1" > "$card_html"
grep --quiet "CI management comment" "$card_html"
grep --quiet "added a comment" "$card_html"

printf 'Tabor Lane attachment smoke test\n' > "$attachment_payload"
attachment_size="$(wc -c < "$attachment_payload" | tr -d ' ')"
presign_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id/attachments/presign" \
    --data-urlencode "csrfToken=$card_csrf_token" \
    --data-urlencode "filename=ci-attachment.txt" \
    --data-urlencode "contentType=text/plain" \
    --data-urlencode "size=$attachment_size"
)"
attachment_id="$(printf '%s' "$presign_response" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
upload_url="$(printf '%s' "$presign_response" | sed -n 's/.*"uploadUrl":"\([^"]*\)".*/\1/p')"
test -n "$attachment_id"
test -n "$upload_url"

upload_status="$(
  curl --silent --show-error --output "$attachment_download" --write-out '%{http_code}' \
    --request PUT --header "Content-Type: text/plain" \
    --upload-file "$attachment_payload" "$upload_url"
)"
if [[ "$upload_status" != 2* ]]; then
  echo "Presigned attachment upload returned HTTP $upload_status" >&2
  cat "$attachment_download" >&2
  exit 1
fi

complete_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id/attachments/$attachment_id/complete" \
    --data-urlencode "csrfToken=$card_csrf_token"
)"
printf '%s' "$complete_response" | grep --quiet '"success":true'

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$managed_card_id?attached=1" > "$card_html"
grep --quiet "ci-attachment.txt" "$card_html"
grep --quiet "added an attachment" "$card_html"
grep --quiet 'id="card-attachments" class="card-panel"' "$card_html"
grep --quiet 'target="_blank" rel="noopener"' "$card_html"
grep --quiet 'hx-target="#card-attachments"' "$card_html"
curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
grep --quiet 'data-card-attachments' "$app_html"
grep --quiet "ci-attachment.txt" "$app_html"

curl --fail --silent --show-error --location --cookie "$cookie_jar" \
  "$base_url/app/attachments/$attachment_id/download" > "$attachment_download"
cmp "$attachment_payload" "$attachment_download"

attachment_remove_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id/attachments/$attachment_id/remove" \
    --data-urlencode "csrfToken=$card_csrf_token"
)"
test "$attachment_remove_status" = "302"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$managed_card_id?attachmentRemoved=1" > "$card_html"
if grep --quiet "ci-attachment.txt" "$card_html"; then
  echo "Removed attachment remained visible on the card" >&2
  exit 1
fi
grep --quiet "removed an attachment" "$card_html"
curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
if grep --quiet "ci-attachment.txt" "$app_html"; then
  echo "Removed attachment remained visible in the board tooltip" >&2
  exit 1
fi

card_archive_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id/archive" \
    --data-urlencode "csrfToken=$card_csrf_token"
)"
test "$card_archive_status" = "302"
curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
if grep --quiet "CI managed card" "$app_html"; then
  echo "Archived card remained visible on the active board" >&2
  exit 1
fi

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
    --data-urlencode "inviteeName=CI Invited Member" \
    --data-urlencode "email=$invite_email" \
    --data-urlencode "role=member"
)"
test "$invite_status" = "302"

curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app/members" > "$members_html"
grep --quiet "CI Invited Member" "$members_html"
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
if ! grep 'name="displayName"' "$member_signup_html" | grep --quiet 'value="CI&#x20;Invited&#x20;Member"'; then
  echo "Invited member name was not prefilled on signup" >&2
  grep 'name="displayName"' "$member_signup_html" >&2 || true
  exit 1
fi

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

curl --fail --silent --show-error --location \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  "$base_url/locale/pt_BR" > /dev/null
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$card_id" > "$card_html"
grep --quiet "Detalhes do card" "$card_html"
grep --quiet "Prioridade" "$card_html"

echo "Functional smoke test passed"
