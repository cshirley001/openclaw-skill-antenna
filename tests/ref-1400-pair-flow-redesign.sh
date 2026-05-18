#!/usr/bin/env bash
# REF-1400 regression test: antenna pair starts with a transport menu and keeps
# Email / ClawReef / Manual pairing paths as distinct wizard branches.
#
# Structural coverage only. The wizard is intentionally interactive; this test
# protects the agreed state-machine shape without sending email or opening
# browsers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
PAIR="$SKILL_REPO/scripts/antenna-pair.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '      %s\n' "$2"; }

echo "── REF-1400 pairing flow redesign ──"

# T1: top-level transport menu exists.
for needle in \
  'How would you like to pair?' \
  '1) Email (requires Himalaya or gog)' \
  '2) ClawReef.io invite' \
  '3) Manually' \
  '4) Quit'
do
  if grep -F "$needle" "$PAIR" >/dev/null; then
    pass "T1: menu contains '$needle'"
  else
    fail "T1: menu contains '$needle'"
  fi
done

# T2: each pairing path is its own function.
for fn in run_email_pairing run_email_bundle_invite run_email_pubkey_request run_clawreef_pairing run_manual_pairing; do
  if grep -qE "^${fn}\(\)" "$PAIR"; then
    pass "T2.${fn}: function defined"
  else
    fail "T2.${fn}: function defined"
  fi
done

# T3: email branch supports both agreed phases.
_email_region="$(awk '/^run_email_pairing\(\)/,/^run_manual_pairing\(\)/' "$PAIR")"
if printf '%s\n' "$_email_region" | grep -F 'Enter recipient PubKey' >/dev/null \
   && printf '%s\n' "$_email_region" | grep -F 'Send PubKey Request Email' >/dev/null; then
  pass "T3: email branch offers bundle invite and pubkey request paths"
else
  fail "T3: email branch offers bundle invite and pubkey request paths"
fi

# T4: email field limits are enforced through the shared prompt helper.
if grep -F 'prompt_limited_value subject "Subject (< 50 characters)" 50' "$PAIR" >/dev/null \
   && grep -F 'prompt_limited_value message "Any message to include (< 100 characters)" 100' "$PAIR" >/dev/null; then
  pass "T4: subject/message length limits are wired"
else
  fail "T4: subject/message length limits are wired"
fi

# T5: outbound email paths preview before asking to send.
_bundle_invite_region="$(awk '/^run_email_bundle_invite\(\)/,/^run_email_pairing\(\)/' "$PAIR")"
preview_line="$(printf '%s\n' "$_bundle_invite_region" | awk '/show_email_preview/ { print NR; exit }')"
send_line="$(printf '%s\n' "$_bundle_invite_region" | awk '/Send this email\?/ { print NR; exit }')"
if [[ -n "$preview_line" && -n "$send_line" && "$preview_line" -lt "$send_line" ]]; then
  pass "T5.bundle: preview comes before send confirmation"
else
  fail "T5.bundle: preview comes before send confirmation"
fi

_pubkey_request_region="$(awk '/^run_email_pubkey_request\(\)/,/^run_email_bundle_invite\(\)/' "$PAIR")"
preview_line="$(printf '%s\n' "$_pubkey_request_region" | awk '/show_email_preview/ { print NR; exit }')"
send_line="$(printf '%s\n' "$_pubkey_request_region" | awk '/Send this email\?/ { print NR; exit }')"
if [[ -n "$preview_line" && -n "$send_line" && "$preview_line" -lt "$send_line" ]]; then
  pass "T5.pubkey: preview comes before send confirmation"
else
  fail "T5.pubkey: preview comes before send confirmation"
fi

# T6: email branch delegates actual sends to antenna peers exchange with the
# new helper options, rather than duplicating MIME/backend code in the wizard.
if grep -F 'build_email_args' "$PAIR" >/dev/null \
   && grep -F -- '--subject "$subject"' "$PAIR" >/dev/null \
   && grep -F -- '--message "$message"' "$PAIR" >/dev/null \
   && grep -F -- '--cc-self' "$PAIR" >/dev/null; then
  pass "T6: wizard delegates email sends with subject/message/cc-self options"
else
  fail "T6: wizard delegates email sends with subject/message/cc-self options"
fi

# T7: only CC-to-self is offered; no arbitrary CC address prompt.
if grep -F 'CC yourself for confirmation?' "$PAIR" >/dev/null \
   && ! grep -Ei 'prompt_value[[:space:]]+[A-Za-z0-9_]*cc|cc address|arbitrary cc' "$PAIR" >/dev/null; then
  pass "T7: CC support is limited to CC-to-self"
else
  fail "T7: CC support is limited to CC-to-self" "found possible arbitrary CC prompt"
fi

# T8: prompt_limited_value must preserve the operator's input. This catches a
# Bash dynamic-scoping bug where using the temp name "value" collided with
# prompt_value's local variable, leaving preview subject/body blank and forcing
# the send helper to fall back to default email text.
tmp_pair_source="$(mktemp)"
trap 'rm -f "$tmp_pair_source"' EXIT
sed '$s/^run_transport_menu$/# run_transport_menu/' "$PAIR" > "$tmp_pair_source"
if (
  set --
  # shellcheck disable=SC1090
  source "$tmp_pair_source"
  subject=""
  message=""
  prompt_limited_value subject "Subject (< 50 characters)" 50 "Default Subject" <<<"Custom Subject"
  prompt_limited_value message "Any message to include (< 100 characters)" 100 "" <<<"Custom message"
  [[ "$subject" == "Custom Subject" && "$message" == "Custom message" ]]
); then
  pass "T8: limited prompt preserves custom subject/message"
else
  fail "T8: limited prompt preserves custom subject/message"
fi

# T9: build_email_args must return success when CC-to-self is disabled. The
# wizard runs under set -e, so a trailing false [[ cc_self == true ]] test used
# to abort the Manual path before it printed/sent the email.
if (
  set --
  # shellcheck disable=SC1090
  source "$tmp_pair_source"
  args=(peers exchange initiate bob --pubkey age1example --output /tmp/bundle.age.txt)
  build_email_args args "peer@example.com" "msi_mail" "Subject" "Message" "false"
  printf '%s\n' "${args[*]}" | grep -F -- '--send-email' >/dev/null
); then
  pass "T9: email arg builder succeeds when CC-self is off"
else
  fail "T9: email arg builder succeeds when CC-self is off"
fi

echo ""
printf 'Result: \033[32m%s passed\033[0m, \033[31m%s failed\033[0m\n' "$PASS" "$FAIL"

if (( FAIL > 0 )); then
  exit 1
fi
