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
avatar_payload="$(mktemp)"
avatar_before="$(mktemp)"
avatar_after="$(mktemp)"
boards_html="$(mktemp)"
my_work_html="$(mktemp)"
trap 'rm -f "$cookie_jar" "$signup_html" "$app_html" "$check_email_html" "$members_html" "$billing_html" "$profile_html" "$card_html" "$partial_html" "$history_restore_html" "$invitation_html" "$member_cookie_jar" "$member_signup_html" "$attachment_payload" "$attachment_download" "$avatar_payload" "$avatar_before" "$avatar_after" "$boards_html" "$my_work_html"' EXIT

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
grep --quiet 'class="workspace-picker"' "$app_html"
grep --quiet 'class="user-avatar account-avatar"' "$app_html"
if grep --quiet 'workspace-picker-menu' "$app_html"; then
  echo "Single-workspace account unexpectedly displayed a workspace dropdown" >&2
  exit 1
fi
if sed -n '/<header class="workspace-header">/,/<\/header>/p' "$app_html" | grep --quiet 'account-avatar'; then
  echo "Boards header unexpectedly displayed the current user avatar" >&2
  exit 1
fi

for partial_path in app app/my-work app/members app/profile app/billing app/boards/manage; do
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
grep --quiet 'id="profile-avatar"' "$profile_html"
grep --quiet 'data-avatar-manager' "$profile_html"
grep --quiet 'data-avatar-stage' "$profile_html"
grep --quiet 'accept="image/jpeg,image/png,image/webp"' "$profile_html"
avatar_csrf="$(
  sed -n 's/.*data-avatar-csrf-token="\([^"]*\)".*/\1/p' "$profile_html" | head -1
)"
test -n "$avatar_csrf"
invalid_avatar_csrf_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/presign" \
    --data-urlencode "csrfToken=invalid" \
    --data-urlencode "filename=avatar.png" \
    --data-urlencode "sourceContentType=image/png" \
    --data-urlencode "sourceSize=1024" \
    --data-urlencode "outputSize=1024"
)"
test "$invalid_avatar_csrf_status" = "403"
invalid_avatar_type_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/presign" \
    --data-urlencode "csrfToken=$avatar_csrf" \
    --data-urlencode "filename=avatar.svg" \
    --data-urlencode "sourceContentType=image/svg+xml" \
    --data-urlencode "sourceSize=1024" \
    --data-urlencode "outputSize=1024"
)"
test "$invalid_avatar_type_status" = "422"
grep --quiet '"code":"invalid_type"' "$partial_html"
large_avatar_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/presign" \
    --data-urlencode "csrfToken=$avatar_csrf" \
    --data-urlencode "filename=avatar.png" \
    --data-urlencode "sourceContentType=image/png" \
    --data-urlencode "sourceSize=5242881" \
    --data-urlencode "outputSize=1024"
)"
test "$large_avatar_status" = "422"
grep --quiet '"code":"source_too_large"' "$partial_html"
base64 --decode scripts/fixtures/avatar-512.jpg.gz.b64 | gzip --decompress > "$avatar_payload"
avatar_size="$(wc -c < "$avatar_payload" | tr -d ' ')"
test "$avatar_size" = "4724"
avatar_presign="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/presign" \
    --data-urlencode "csrfToken=$avatar_csrf" \
    --data-urlencode "filename=ci-avatar.jpg" \
    --data-urlencode "sourceContentType=image/jpeg" \
    --data-urlencode "sourceSize=$avatar_size" \
    --data-urlencode "outputSize=$avatar_size"
)"
avatar_id="$(printf '%s' "$avatar_presign" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
avatar_upload_url="$(printf '%s' "$avatar_presign" | sed -n 's/.*"uploadUrl":"\([^"]*\)".*/\1/p')"
test -n "$avatar_id"
test -n "$avatar_upload_url"
avatar_upload_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --request PUT --header "Content-Type: image/jpeg" \
    --upload-file "$avatar_payload" "$avatar_upload_url"
)"
test "$avatar_upload_status" = "200"
avatar_complete="$(
  curl --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/$avatar_id/complete" \
    --data-urlencode "csrfToken=$avatar_csrf"
)"
if ! printf '%s' "$avatar_complete" | grep --quiet '"success":true'; then
  echo "Unexpected avatar completion response: $avatar_complete" >&2
  exit 1
fi
avatar_path="$(printf '%s' "$avatar_complete" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
test -n "$avatar_path"
curl --fail --silent --show-error --location --cookie "$cookie_jar" \
  "$base_url$avatar_path" > "$avatar_before"
test -s "$avatar_before"

second_complete_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/$avatar_id/complete" \
    --data-urlencode "csrfToken=$avatar_csrf"
)"
test "$second_complete_status" = "200"
grep --quiet '"success":true' "$partial_html"
printf 'not a validated jpeg\n' > "$avatar_after"
reuse_upload_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --request PUT --header "Content-Type: image/jpeg" \
    --upload-file "$avatar_after" "$avatar_upload_url"
)"
test "$reuse_upload_status" = "200"
curl --fail --silent --show-error --location --cookie "$cookie_jar" \
  "$base_url$avatar_path" > "$avatar_after"
cmp "$avatar_before" "$avatar_after"

avatar_remove_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/profile/avatar/remove" \
    --data-urlencode "csrfToken=$avatar_csrf"
)"
test "$avatar_remove_status" = "200"
grep --quiet '"success":true' "$partial_html"
removed_avatar_status="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --cookie "$cookie_jar" "$base_url$avatar_path"
)"
test "$removed_avatar_status" = "404"
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
last_column_id="$(grep -o 'data-column-id="[^"]*"' "$app_html" | tail -1 | cut -d'"' -f2)"
card_id="$(grep -o 'data-card-id="[^"]*"' "$app_html" | head -1 | cut -d'"' -f2)"
test -n "$csrf_token"
test -n "$column_id"
test -n "$target_column_id"
test -n "$last_column_id"
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
owner_user_id="$(
  grep -o 'value="[^"]*"[^>]*>CI Owner Updated</option>' "$card_html" \
    | head -1 | sed -n 's/value="\([^"]*\)".*/\1/p'
)"
test -n "$card_csrf_token"
test -n "$owner_user_id"
upcoming_date="$(date -u -d '+5 days' +%F)"
today_date="$(date -u +%F)"

card_update_result="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id" \
    --data-urlencode "csrfToken=$card_csrf_token" \
    --data-urlencode "title=CI managed card" \
    --data-urlencode "description=Updated through card management" \
    --data-urlencode "priority=high" \
    --data-urlencode "assigneeId=$owner_user_id" \
    --data-urlencode "dueDate=$upcoming_date" \
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

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/my-work" > "$my_work_html"
grep --quiet '<!doctype html>' "$my_work_html"
grep --quiet 'class="workspace-sidebar"' "$my_work_html"
grep --quiet 'data-workspace-page="myWork"' "$my_work_html"
grep --quiet 'href="/app/my-work" class="active"' "$my_work_html"
grep --quiet '<span data-avatar-initials>CU</span>' "$my_work_html"
if sed -n '/<header class="workspace-header my-work-header">/,/<\/header>/p' "$my_work_html" | grep --quiet 'account-avatar'; then
  echo "My Work header unexpectedly displayed the current user avatar" >&2
  exit 1
fi
grep --quiet "CI managed card" "$my_work_html"
grep 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
  | grep --quiet 'data-my-work-group="upcoming".*data-priority="high"'
my_work_csrf="$(
  grep -A 30 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
    | sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' | head -1
)"
my_work_version="$(
  grep -A 30 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
    | sed -n 's/.*name="version" value="\([^"]*\)".*/\1/p' | head -1
)"
test -n "$my_work_csrf"
test -n "$my_work_version"

curl --fail --silent --show-error --get --cookie "$cookie_jar" \
  --data-urlencode "priority=high" "$base_url/app/my-work" > "$my_work_html"
grep --quiet "CI managed card" "$my_work_html"
curl --fail --silent --show-error --get --cookie "$cookie_jar" \
  --data-urlencode "query=CI no matching work" "$base_url/app/my-work" > "$my_work_html"
grep --quiet "No cards match these filters" "$my_work_html"
if grep --quiet "CI managed card" "$my_work_html"; then
  echo "My Work search returned a card that does not match" >&2
  exit 1
fi

quick_update_status="$(
  curl --silent --show-error --output "$my_work_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --header "HX-Request: true" \
    --request POST "$base_url/app/my-work/cards/$managed_card_id" \
    --data-urlencode "csrfToken=$my_work_csrf" \
    --data-urlencode "version=$my_work_version" \
    --data-urlencode "priority=urgent" \
    --data-urlencode "dueDate=$today_date" \
    --data-urlencode "due=all" \
    --data-urlencode "sort=due"
)"
test "$quick_update_status" = "200"
grep --quiet 'id="my-work-results"' "$my_work_html"
grep --quiet "Card updated and reorganized" "$my_work_html"
grep 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
  | grep --quiet 'data-my-work-group="today".*data-priority="urgent"'
if grep --quiet '<!doctype html>' "$my_work_html" || grep --quiet 'class="workspace-sidebar"' "$my_work_html"; then
  echo "My Work quick update unexpectedly returned the full document" >&2
  exit 1
fi

invalid_my_work_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --header "HX-Request: true" \
    --request POST "$base_url/app/my-work/cards/$managed_card_id" \
    --data-urlencode "csrfToken=invalid" \
    --data-urlencode "version=$my_work_version" \
    --data-urlencode "priority=low" \
    --data-urlencode "dueDate="
)"
test "$invalid_my_work_status" = "403"

curl --fail --silent --show-error --get --cookie "$cookie_jar" \
  --data-urlencode "due=today" "$base_url/app/my-work" > "$my_work_html"
grep 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
  | grep --quiet 'data-my-work-group="today".*data-priority="urgent"'
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/my-work" > "$my_work_html"
grep --quiet '<option value="today" selected>Due today</option>' "$my_work_html"
grep 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
  | grep --quiet 'data-my-work-group="today".*data-priority="urgent"'
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$managed_card_id?returnTo=my-work" > "$card_html"
grep --quiet "Back to My work" "$card_html"
grep --quiet 'data-workspace-page="myWork"' "$card_html"

complete_card_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$managed_card_id/move" \
    --data-urlencode "csrfToken=$card_csrf_token" \
    --data-urlencode "columnId=$last_column_id"
)"
printf '%s' "$complete_card_response" | grep --quiet '"success":true'
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/my-work?resetFilters=1" > "$my_work_html"
grep 'data-my-work-card="'"$managed_card_id"'"' "$my_work_html" \
  | grep --quiet 'data-my-work-group="completed".*data-priority="urgent"'
grep --quiet "Completed recently" "$my_work_html"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/my-work" > "$my_work_html"
grep --quiet '<option value="all" selected>All dates</option>' "$my_work_html"

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

initial_board_id="$(sed -n 's/.*data-board-id="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
test -n "$initial_board_id"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage" > "$boards_html"
grep --quiet "Boards and lanes" "$boards_html"
board_csrf_token="$(
  sed -n '/action="\/app\/boards"/,/<\/form>/ s/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    "$boards_html" | head -1
)"
test -n "$board_csrf_token"

board_create_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards" \
    --data-urlencode "csrfToken=$board_csrf_token" \
    --data-urlencode "name=CI Software Board" \
    --data-urlencode "description=Created by the functional smoke test" \
    --data-urlencode "template=software"
)"
managed_board_id="$(printf '%s' "$board_create_redirect" | sed -n 's/.*boardId=\([^&]*\).*/\1/p')"
managed_board_id="${managed_board_id//%2D/-}"
managed_board_id="${managed_board_id//%2d/-}"
if [[ -z "$managed_board_id" ]]; then
  echo "Board creation returned unexpected redirect: $board_create_redirect" >&2
  exit 1
fi

board_move_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards/$managed_board_id/move" \
    --data-urlencode "csrfToken=$board_csrf_token" \
    --data-urlencode "direction=left"
)"
curl --fail --silent --show-error --cookie "$cookie_jar" "$board_move_redirect" > "$boards_html"
grep --quiet "Board order updated" "$boards_html"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep --quiet "CI Software Board" "$app_html"
if ! grep --quiet "Ready" "$app_html"; then
  selected_board_id="$(sed -n 's/.*data-board-id="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
  echo "Requested board $managed_board_id but application selected $selected_board_id" >&2
  exit 1
fi
grep --quiet 'class="board-switcher"' "$app_html"
grep --quiet "/app/boards/manage?boardId=$managed_board_id" "$app_html"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
board_csrf_token="$(
  sed -n '/action="\/app\/boards\/[^"]*\/update"/,/<\/form>/ s/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    "$boards_html" | head -1
)"
test -n "$board_csrf_token"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes" \
  --data-urlencode "csrfToken=$board_csrf_token" \
  --data-urlencode "name=QA Lane" \
  --data-urlencode "color=blue" \
  --data-urlencode "wipLimit=2"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
qa_lane_id="$(sed -n 's/.*data-lane-id="\([^"]*\)" data-lane-name="QA&#x20;Lane".*/\1/p' "$boards_html" | head -1)"
test -n "$qa_lane_id"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes/$qa_lane_id/update" \
  --data-urlencode "csrfToken=$board_csrf_token" \
  --data-urlencode "name=QA Review" \
  --data-urlencode "color=purple" \
  --data-urlencode "wipLimit=1"
curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes/$qa_lane_id/move" \
  --data-urlencode "csrfToken=$board_csrf_token" \
  --data-urlencode "direction=up"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
grep 'data-lane-id="'"$qa_lane_id"'"' "$boards_html" \
  | grep 'lane-color-purple' \
  | grep --quiet 'data-lane-name="QA&#x20;Review"'
grep --quiet 'name="wipLimit" type="number" min="1" max="999" value="1"' "$boards_html"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
board_card_csrf="$(sed -n 's/.*data-csrf-token="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
target_lane_id="$(sed -n 's/.*data-column-id="\([^"]*\)".*/\1/p' "$app_html" | grep -v "$qa_lane_id" | head -1)"
test -n "$board_card_csrf"
test -n "$target_lane_id"
curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/cards" \
  --data-urlencode "csrfToken=$board_card_csrf" \
  --data-urlencode "title=CI lane safety card" \
  --data-urlencode "columnId=$qa_lane_id"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
lane_safety_card_id="$(sed -n 's/.*data-card-id="\([^"]*\)" data-card-title="CI&#x20;lane&#x20;safety&#x20;card".*/\1/p' "$app_html" | head -1)"
test -n "$lane_safety_card_id"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/cards" \
  --data-urlencode "csrfToken=$board_card_csrf" \
  --data-urlencode "title=CI WIP candidate" \
  --data-urlencode "columnId=$target_lane_id"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
wip_candidate_id="$(sed -n 's/.*data-card-id="\([^"]*\)" data-card-title="CI&#x20;WIP&#x20;candidate".*/\1/p' "$app_html" | head -1)"
test -n "$wip_candidate_id"
wip_move_status="$(
  curl --silent --show-error --output "$attachment_download" --write-out '%{http_code}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$wip_candidate_id/move" \
    --data-urlencode "csrfToken=$board_card_csrf" \
    --data-urlencode "columnId=$qa_lane_id"
)"
test "$wip_move_status" = "409"
grep --quiet '"code":"wip_limit"' "$attachment_download"

lane_delete_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards/$managed_board_id/lanes/$qa_lane_id/delete" \
    --data-urlencode "csrfToken=$board_csrf_token"
)"
curl --fail --silent --show-error --cookie "$cookie_jar" "$lane_delete_redirect" > "$boards_html"
grep --quiet "contains cards and cannot be deleted" "$boards_html"

move_safety_card_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$lane_safety_card_id/move" \
    --data-urlencode "csrfToken=$board_card_csrf" \
    --data-urlencode "columnId=$target_lane_id"
)"
printf '%s' "$move_safety_card_response" | grep --quiet '"success":true'

reorder_card_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$lane_safety_card_id/move" \
    --data-urlencode "csrfToken=$board_card_csrf" \
    --data-urlencode "columnId=$target_lane_id" \
    --data-urlencode "beforeCardId=$wip_candidate_id"
)"
printf '%s' "$reorder_card_response" | grep --quiet '"success":true'
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
safety_card_line="$(grep -n 'data-card-title="CI&#x20;lane&#x20;safety&#x20;card"' "$app_html" | head -1 | cut -d: -f1)"
candidate_card_line="$(grep -n 'data-card-title="CI&#x20;WIP&#x20;candidate"' "$app_html" | head -1 | cut -d: -f1)"
if [[ -z "$safety_card_line" || -z "$candidate_card_line" || "$safety_card_line" -ge "$candidate_card_line" ]]; then
  echo "Same-lane card ordering was not persisted" >&2
  exit 1
fi

lane_layout_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/lanes/$target_lane_id/layout" \
    --data-urlencode "csrfToken=$board_card_csrf" \
    --data-urlencode "widthPx=620" \
    --data-urlencode "isCollapsed=true"
)"
printf '%s' "$lane_layout_response" | grep --quiet '"success":true'
printf '%s' "$lane_layout_response" | grep --quiet '"widthPx":620'
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep 'data-column-id="'"$target_lane_id"'"' "$app_html" \
  | grep --quiet 'is-collapsed.*data-lane-width="620".*data-lane-collapsed="true"'

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/lanes/$target_lane_id/layout" \
  --data-urlencode "csrfToken=$board_card_csrf" \
  --data-urlencode "widthPx=620" \
  --data-urlencode "isCollapsed=false"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes/$qa_lane_id/delete" \
  --data-urlencode "csrfToken=$board_csrf_token"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
if grep --quiet 'data-lane-id="'"$qa_lane_id"'"' "$boards_html"; then
  echo "Empty lane remained visible after deletion" >&2
  exit 1
fi

board_update_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards/$managed_board_id/update" \
    --data-urlencode "csrfToken=$board_csrf_token" \
    --data-urlencode "name=CI Delivery Board" \
    --data-urlencode "description=Updated board"
)"
curl --fail --silent --show-error --cookie "$cookie_jar" "$board_update_redirect" > "$boards_html"
grep --quiet "CI Delivery Board" "$boards_html"

third_board_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards" \
    --data-urlencode "csrfToken=$board_csrf_token" \
    --data-urlencode "name=CI Personal Board" \
    --data-urlencode "template=personal"
)"
third_board_id="$(printf '%s' "$third_board_redirect" | sed -n 's/.*boardId=\([^&]*\).*/\1/p')"
third_board_id="${third_board_id//%2D/-}"
third_board_id="${third_board_id//%2d/-}"
test -n "$third_board_id"
fourth_board_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards" \
    --data-urlencode "csrfToken=$board_csrf_token" \
    --data-urlencode "name=CI Board Above Free Limit" \
    --data-urlencode "template=blank"
)"
curl --fail --silent --show-error --cookie "$cookie_jar" "$fourth_board_redirect" > "$boards_html"
grep --quiet "Free plan allows up to 3 active boards" "$boards_html"

for board_to_archive in "$third_board_id" "$managed_board_id"; do
  curl --fail --silent --show-error --output /dev/null \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards/$board_to_archive/archive" \
    --data-urlencode "csrfToken=$board_csrf_token"
done
last_board_redirect="$(
  curl --silent --show-error --output /dev/null --write-out '%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/boards/$initial_board_id/archive" \
    --data-urlencode "csrfToken=$board_csrf_token"
)"
curl --fail --silent --show-error --cookie "$cookie_jar" "$last_board_redirect" > "$boards_html"
grep --quiet "must keep at least one active board" "$boards_html"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/restore" \
  --data-urlencode "csrfToken=$board_csrf_token"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep --quiet "CI Delivery Board" "$app_html"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
board_csrf_token="$(
  sed -n '/action="\/app\/boards\/[^"]*\/update"/,/<\/form>/ s/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    "$boards_html" | head -1
)"
test -n "$board_csrf_token"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes" \
  --data-urlencode "csrfToken=$board_csrf_token" \
  --data-urlencode "name=CI Hidden Archive" \
  --data-urlencode "color=slate" \
  --data-urlencode "wipLimit=" \
  --data-urlencode "hiddenFromMembers=1"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
hidden_lane_id="$(
  sed -n '/data-lane-name="CI&#x20;Hidden&#x20;Archive"/ s/.*data-lane-id="\([^"]*\)".*/\1/p' \
    "$boards_html" | head -1
)"
test -n "$hidden_lane_id"
grep 'data-lane-id="'"$hidden_lane_id"'"' "$boards_html" \
  | grep --quiet 'data-hidden-from-members="true"'
grep --quiet "Hidden from members" "$boards_html"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep 'data-column-id="'"$hidden_lane_id"'"' "$app_html" \
  | grep --quiet 'is-hidden-from-members'
grep --quiet "CI Hidden Archive" "$app_html"
board_card_csrf="$(sed -n 's/.*data-csrf-token="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
test -n "$board_card_csrf"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/cards" \
  --data-urlencode "csrfToken=$board_card_csrf" \
  --data-urlencode "title=CI hidden archive card" \
  --data-urlencode "description=Visible only to workspace administrators" \
  --data-urlencode "columnId=$hidden_lane_id"
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
hidden_card_id="$(
  sed -n '/data-card-title="CI&#x20;hidden&#x20;archive&#x20;card"/ s/.*data-card-id="\([^"]*\)".*/\1/p' \
    "$app_html" | head -1
)"
test -n "$hidden_card_id"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$hidden_card_id" > "$card_html"
hidden_card_csrf="$(sed -n 's/.*data-card-csrf-token="\([^"]*\)".*/\1/p' "$card_html" | head -1)"
test -n "$hidden_card_csrf"
printf 'Hidden lane attachment smoke test\n' > "$attachment_payload"
hidden_attachment_size="$(wc -c < "$attachment_payload" | tr -d ' ')"
hidden_presign_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$hidden_card_id/attachments/presign" \
    --data-urlencode "csrfToken=$hidden_card_csrf" \
    --data-urlencode "filename=hidden-archive.txt" \
    --data-urlencode "contentType=text/plain" \
    --data-urlencode "size=$hidden_attachment_size"
)"
hidden_attachment_id="$(printf '%s' "$hidden_presign_response" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
hidden_upload_url="$(printf '%s' "$hidden_presign_response" | sed -n 's/.*"uploadUrl":"\([^"]*\)".*/\1/p')"
test -n "$hidden_attachment_id"
test -n "$hidden_upload_url"
hidden_upload_status="$(
  curl --silent --show-error --output "$attachment_download" --write-out '%{http_code}' \
    --request PUT --header "Content-Type: text/plain" \
    --upload-file "$attachment_payload" "$hidden_upload_url"
)"
if [[ "$hidden_upload_status" != 2* ]]; then
  echo "Hidden-lane attachment upload returned HTTP $hidden_upload_status" >&2
  cat "$attachment_download" >&2
  exit 1
fi
hidden_complete_response="$(
  curl --fail --silent --show-error \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$hidden_card_id/attachments/$hidden_attachment_id/complete" \
    --data-urlencode "csrfToken=$hidden_card_csrf"
)"
printf '%s' "$hidden_complete_response" | grep --quiet '"success":true'

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

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$hidden_card_id" > "$card_html"
hidden_card_csrf="$(sed -n 's/.*data-card-csrf-token="\([^"]*\)".*/\1/p' "$card_html" | head -1)"
member_user_id="$(
  grep -o 'value="[^"]*"[^>]*>CI Member</option>' "$card_html" \
    | head -1 | sed -n 's/value="\([^"]*\)".*/\1/p'
)"
test -n "$hidden_card_csrf"
test -n "$member_user_id"
hidden_card_update_result="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/app/cards/$hidden_card_id" \
    --data-urlencode "csrfToken=$hidden_card_csrf" \
    --data-urlencode "title=CI hidden archive card" \
    --data-urlencode "description=Visible only to workspace administrators" \
    --data-urlencode "priority=low" \
    --data-urlencode "assigneeId=$member_user_id" \
    --data-urlencode "dueDate=" \
    --data-urlencode "labels=archive"
)"
if [[ "$hidden_card_update_result" != 302*"updated=1" ]]; then
  echo "Assigning the hidden card returned an unexpected result: $hidden_card_update_result" >&2
  exit 1
fi

curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep --quiet "CI Workspace" "$app_html"
grep --quiet "member" "$app_html"
if grep --quiet -E "CI Hidden Archive|CI hidden archive card|hidden-archive.txt|$hidden_lane_id|$hidden_card_id" "$app_html"; then
  echo "The board exposed a hidden lane or one of its resources to a member" >&2
  exit 1
fi
member_card_csrf="$(sed -n 's/.*data-csrf-token="\([^"]*\)".*/\1/p' "$app_html" | head -1)"
test -n "$member_card_csrf"

curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
if grep --quiet -E "CI Hidden Archive|$hidden_lane_id|data-hidden-from-members=\"true\"" "$boards_html"; then
  echo "Board management exposed a hidden lane to a member" >&2
  exit 1
fi

hidden_card_direct_result="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
    --cookie "$member_cookie_jar" "$base_url/app/cards/$hidden_card_id"
)"
if [[ "$hidden_card_direct_result" != 302*"/app" ]]; then
  echo "Direct hidden-card access returned an unexpected result: $hidden_card_direct_result" >&2
  exit 1
fi

hidden_move_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
    --request POST "$base_url/app/cards/$lane_safety_card_id/move" \
    --data-urlencode "csrfToken=$member_card_csrf" \
    --data-urlencode "columnId=$hidden_lane_id"
)"
test "$hidden_move_status" = "403"
grep --quiet '"code":"forbidden"' "$partial_html"

hidden_layout_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
    --request POST "$base_url/app/lanes/$hidden_lane_id/layout" \
    --data-urlencode "csrfToken=$member_card_csrf" \
    --data-urlencode "widthPx=640" \
    --data-urlencode "isCollapsed=true"
)"
test "$hidden_layout_status" = "403"
grep --quiet '"code":"forbidden"' "$partial_html"

hidden_presign_status="$(
  curl --silent --show-error --output "$partial_html" --write-out '%{http_code}' \
    --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
    --request POST "$base_url/app/cards/$hidden_card_id/attachments/presign" \
    --data-urlencode "csrfToken=$member_card_csrf" \
    --data-urlencode "filename=member-bypass.txt" \
    --data-urlencode "contentType=text/plain" \
    --data-urlencode "size=20"
)"
test "$hidden_presign_status" = "422"
grep --quiet '"code":"forbidden"' "$partial_html"

hidden_download_result="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
    --cookie "$member_cookie_jar" "$base_url/app/attachments/$hidden_attachment_id/download"
)"
if [[ "$hidden_download_result" != 302*"/app" ]]; then
  echo "Direct hidden-attachment access returned an unexpected result: $hidden_download_result" >&2
  exit 1
fi

hidden_create_result="$(
  curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
    --cookie "$member_cookie_jar" --cookie-jar "$member_cookie_jar" \
    --request POST "$base_url/app/cards" \
    --data-urlencode "csrfToken=$member_card_csrf" \
    --data-urlencode "columnId=$hidden_lane_id" \
    --data-urlencode "title=CI member hidden bypass"
)"
if [[ "$hidden_create_result" != 302*"/app" ]]; then
  echo "Creating a card in a hidden lane returned an unexpected result: $hidden_create_result" >&2
  exit 1
fi

curl --fail --silent --show-error --cookie "$member_cookie_jar" "$base_url/app/my-work" > "$my_work_html"
if grep --quiet "CI managed card" "$my_work_html"; then
  echo "My Work exposed a card assigned to another user" >&2
  exit 1
fi
if grep --quiet -E "CI hidden archive card|CI Hidden Archive|hidden-archive.txt" "$my_work_html"; then
  echo "My Work exposed an assigned card from a hidden lane" >&2
  exit 1
fi
grep --quiet "Nothing assigned to you yet" "$my_work_html"

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/boards/manage?boardId=$managed_board_id" > "$boards_html"
board_csrf_token="$(
  sed -n '/action="\/app\/boards\/[^"]*\/update"/,/<\/form>/ s/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
    "$boards_html" | head -1
)"
test -n "$board_csrf_token"
curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes/$hidden_lane_id/update" \
  --data-urlencode "csrfToken=$board_csrf_token" \
  --data-urlencode "name=CI Hidden Archive" \
  --data-urlencode "color=slate" \
  --data-urlencode "wipLimit=" \
  --data-urlencode "hiddenFromMembers=0"

curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep --quiet "CI Hidden Archive" "$app_html"
grep --quiet "CI hidden archive card" "$app_html"
curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app/cards/$hidden_card_id" > "$card_html"
grep --quiet "hidden-archive.txt" "$card_html"
curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app/my-work" > "$my_work_html"
grep --quiet "CI hidden archive card" "$my_work_html"

curl --fail --silent --show-error --output /dev/null \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --request POST "$base_url/app/boards/$managed_board_id/lanes/$hidden_lane_id/update" \
  --data-urlencode "csrfToken=$board_csrf_token" \
  --data-urlencode "name=CI Hidden Archive" \
  --data-urlencode "color=slate" \
  --data-urlencode "wipLimit=" \
  --data-urlencode "hiddenFromMembers=1"
curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
if grep --quiet -E "CI Hidden Archive|CI hidden archive card|hidden-archive.txt" "$app_html"; then
  echo "A lane remained visible to a member after being hidden again" >&2
  exit 1
fi
curl --fail --silent --show-error --cookie "$member_cookie_jar" \
  "$base_url/app/my-work" > "$my_work_html"
if grep --quiet -E "CI hidden archive card|CI Hidden Archive|hidden-archive.txt" "$my_work_html"; then
  echo "My Work retained a card after its lane was hidden again" >&2
  exit 1
fi

curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app?boardId=$managed_board_id" > "$app_html"
grep --quiet "CI Hidden Archive" "$app_html"
grep --quiet "CI hidden archive card" "$app_html"
grep --quiet "hidden-archive.txt" "$app_html"
if grep --quiet "CI member hidden bypass" "$app_html"; then
  echo "A member created a card in a hidden lane through a known lane ID" >&2
  exit 1
fi

if command -v docker > /dev/null 2>&1 \
  && smoke_db_user="$(docker compose exec -T postgres printenv POSTGRES_USER 2> /dev/null | tr -d '\r')" \
  && smoke_db_name="$(docker compose exec -T postgres printenv POSTGRES_DB 2> /dev/null | tr -d '\r')"; then
  secondary_slug="ci-secondary-$(printf '%s' "$run_id" | tr -cd 'a-zA-Z0-9-' | cut -c1-70)"
  secondary_workspace_id="$(
    printf '%s\n' \
      "WITH new_workspace AS (" \
      "  INSERT INTO workspace(name,slug,plan)" \
      "  VALUES('CI Secondary Workspace', :'secondary_slug', 'free')" \
      "  RETURNING id" \
      "), new_membership AS (" \
      "  INSERT INTO workspace_member(workspace_id,user_id,role)" \
      "  SELECT new_workspace.id,owner_account.id,'owner'" \
      "  FROM new_workspace" \
      "  JOIN app_user owner_account ON owner_account.email=:'owner_email'" \
      "  RETURNING workspace_id" \
      ")" \
      "SELECT workspace_id FROM new_membership;" \
      | docker compose exec -T postgres psql \
        --username "$smoke_db_user" \
        --dbname "$smoke_db_name" \
        --set ON_ERROR_STOP=1 \
        --set secondary_slug="$secondary_slug" \
        --set owner_email="$test_email" \
        --quiet --tuples-only --no-align --file=- \
      | tr -d '\r[:space:]'
  )"
  foreign_workspace_id="$(
    docker compose exec -T postgres psql \
      --username "$smoke_db_user" \
      --dbname "$smoke_db_name" \
      --set ON_ERROR_STOP=1 \
      --quiet --tuples-only --no-align \
      --command "INSERT INTO workspace(name,slug,plan) VALUES('CI Foreign Workspace','${secondary_slug}-foreign','free') RETURNING id;" \
      | tr -d '\r[:space:]'
  )"
  test -n "$secondary_workspace_id"
  test -n "$foreign_workspace_id"

  curl --fail --silent --show-error --cookie "$cookie_jar" "$base_url/app" > "$app_html"
  grep --quiet 'class="workspace-picker-menu"' "$app_html"
  grep --quiet 'CI Secondary Workspace' "$app_html"
  workspace_switch_csrf="$(
    grep -A 3 "action=\"/app/workspaces/$secondary_workspace_id/select\"" "$app_html" \
      | sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' | head -1
  )"
  test -n "$workspace_switch_csrf"

  invalid_workspace_result="$(
    curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
      --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
      --request POST "$base_url/app/workspaces/$secondary_workspace_id/select" \
      --data-urlencode "csrfToken=invalid"
  )"
  if [[ "$invalid_workspace_result" != 302*"workspaceError=invalid" ]]; then
    echo "Invalid workspace CSRF returned an unexpected result: $invalid_workspace_result" >&2
    exit 1
  fi

  select_workspace_result="$(
    curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
      --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
      --request POST "$base_url/app/workspaces/$secondary_workspace_id/select" \
      --data-urlencode "csrfToken=$workspace_switch_csrf"
  )"
  if [[ "$select_workspace_result" != 302*"/app/my-work" ]]; then
    echo "Workspace selection returned an unexpected result: $select_workspace_result" >&2
    exit 1
  fi
  curl --fail --silent --show-error --get --cookie "$cookie_jar" \
    --data-urlencode "due=overdue" "$base_url/app/my-work" > "$my_work_html"
  grep --quiet 'CI Secondary Workspace' "$my_work_html"
  grep --quiet '<option value="overdue" selected>Overdue</option>' "$my_work_html"
  selected_workspace_id="$(
    printf '%s\n' "SELECT last_workspace_id FROM app_user WHERE email=:'owner_email';" \
      | docker compose exec -T postgres psql \
      --username "$smoke_db_user" \
      --dbname "$smoke_db_name" \
      --set owner_email="$test_email" \
      --tuples-only --no-align \
      --file=- \
      | tr -d '\r[:space:]'
  )"
  test "$selected_workspace_id" = "$secondary_workspace_id"

  forbidden_workspace_result="$(
    curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
      --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
      --request POST "$base_url/app/workspaces/$foreign_workspace_id/select" \
      --data-urlencode "csrfToken=$workspace_switch_csrf"
  )"
  if [[ "$forbidden_workspace_result" != 302*"workspaceError=forbidden" ]]; then
    echo "Foreign workspace selection returned an unexpected result: $forbidden_workspace_result" >&2
    exit 1
  fi

  logout_csrf="$(
    sed -n '/action="\/auth\/logout"/,/<\/form>/ s/.*name="csrfToken" value="\([^"]*\)".*/\1/p' \
      "$my_work_html" | head -1
  )"
  test -n "$logout_csrf"
  curl --silent --show-error --output /dev/null \
    --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    --request POST "$base_url/auth/logout" \
    --data-urlencode "csrfToken=$logout_csrf"
  curl --fail --silent --show-error --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
    "$base_url/login" > "$signup_html"
  login_csrf="$(sed -n 's/.*name="csrfToken" value="\([^"]*\)".*/\1/p' "$signup_html" | head -1)"
  test -n "$login_csrf"
  login_result="$(
    curl --silent --show-error --output /dev/null --write-out '%{http_code}|%{redirect_url}' \
      --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
      --request POST "$base_url/auth/login" \
      --data-urlencode "csrfToken=$login_csrf" \
      --data-urlencode "email=$test_email" \
      --data-urlencode "password=CI-updated-password-2026"
  )"
  if [[ "$login_result" != 302*"/app" ]]; then
    echo "Workspace restoration login returned an unexpected result: $login_result" >&2
    exit 1
  fi
  curl --fail --silent --show-error --cookie "$cookie_jar" \
    "$base_url/app/my-work" > "$my_work_html"
  grep --quiet 'CI Secondary Workspace' "$my_work_html"
  grep --quiet '<option value="overdue" selected>Overdue</option>' "$my_work_html"

  printf '%s\n' \
    "DELETE FROM workspace_member" \
    " WHERE workspace_id=CAST(:'secondary_workspace_id' AS UUID)" \
    "   AND user_id=(SELECT id FROM app_user WHERE email=:'owner_email');" \
    | docker compose exec -T postgres psql \
      --username "$smoke_db_user" \
      --dbname "$smoke_db_name" \
      --set ON_ERROR_STOP=1 \
      --set secondary_workspace_id="$secondary_workspace_id" \
      --set owner_email="$test_email" \
      --file=- > /dev/null
  curl --fail --silent --show-error --cookie "$cookie_jar" \
    "$base_url/app/my-work" > "$my_work_html"
  grep --quiet 'CI Workspace' "$my_work_html"
  grep --quiet '<option value="all" selected>All dates</option>' "$my_work_html"
  if grep --quiet 'class="workspace-picker-menu"' "$my_work_html"; then
    echo "Removed workspace remained available in the picker" >&2
    exit 1
  fi
  fallback_workspace_id="$(
    printf '%s\n' "SELECT last_workspace_id FROM app_user WHERE email=:'owner_email';" \
      | docker compose exec -T postgres psql \
      --username "$smoke_db_user" \
      --dbname "$smoke_db_name" \
      --set owner_email="$test_email" \
      --tuples-only --no-align \
      --file=- \
      | tr -d '\r[:space:]'
  )"
  if [[ -z "$fallback_workspace_id" || "$fallback_workspace_id" = "$secondary_workspace_id" ]]; then
    echo "Removed workspace was not repaired in the saved preference" >&2
    exit 1
  fi
  docker compose exec -T postgres psql \
    --username "$smoke_db_user" \
    --dbname "$smoke_db_name" \
    --set ON_ERROR_STOP=1 \
    --command "DELETE FROM workspace WHERE id IN ('$secondary_workspace_id','$foreign_workspace_id');" \
    > /dev/null
fi

curl --fail --silent --show-error --location \
  --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  "$base_url/locale/pt_BR" > /dev/null
curl --fail --silent --show-error --cookie "$cookie_jar" \
  "$base_url/app/cards/$card_id" > "$card_html"
grep --quiet "Detalhes do card" "$card_html"
grep --quiet "Prioridade" "$card_html"

if command -v docker > /dev/null 2>&1 \
  && smoke_db_user="$(docker compose exec -T postgres printenv POSTGRES_USER 2> /dev/null | tr -d '\r')" \
  && smoke_db_name="$(docker compose exec -T postgres printenv POSTGRES_DB 2> /dev/null | tr -d '\r')"; then
  printf '%s\n' \
    "UPDATE card" \
    "   SET assignee_id=(SELECT id FROM app_user WHERE email=:'member_email')" \
    " WHERE id=CAST(:'managed_card_id' AS UUID);" \
    "DELETE FROM workspace_member" \
    " WHERE user_id=(SELECT id FROM app_user WHERE email=:'member_email');" \
    | docker compose exec -T postgres psql \
    --username "$smoke_db_user" \
    --dbname "$smoke_db_name" \
    --set ON_ERROR_STOP=1 \
    --set member_email="$invite_email" \
    --set managed_card_id="$managed_card_id" \
    --file=- > /dev/null
  curl --fail --silent --show-error --cookie "$member_cookie_jar" \
    "$base_url/app/my-work" > "$my_work_html"
  if grep --quiet "CI managed card" "$my_work_html"; then
    echo "My Work exposed workspace data after membership removal" >&2
    exit 1
  fi
fi

echo "Functional smoke test passed"
