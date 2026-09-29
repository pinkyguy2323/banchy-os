#!/usr/bin/env bash
# Six profiles resolve, no duplicate packages, and only gaming/full need multilib.
set -euo pipefail
# shellcheck source=helpers.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

t_setup
# shellcheck source=/dev/null
source "$BANCHY_LIB/common.sh"
# shellcheck source=/dev/null
source "$BANCHY_LIB/profile.sh"

names=()
while IFS= read -r name; do
  if [[ -n "$name" ]]; then
    names+=("$name")
  fi
done < <(b_profile_names)
assert_eq 6 "${#names[@]}" "profile count"

for want in minimal default developer creator gaming full; do
  list_contains "$want" "${names[@]}" || t_fail "missing profile: $want"
done
t_ok "six profiles ship: minimal default developer creator gaming full"

profile_has_flag() {
  local flag="$1" item
  for item in ${B_PROFILE_FLAGS[@]+"${B_PROFILE_FLAGS[@]}"}; do
    if [[ "$item" == "$flag" ]]; then
      return 0
    fi
  done
  return 1
}

for name in "${names[@]}"; do
  if ! b_profile_resolve "$name"; then
    t_fail "profile failed to resolve: $name"
  fi
  if ((${#B_PROFILE_PKGS[@]} == 0)); then
    t_fail "profile resolved to zero packages: $name"
  fi
  dupes="$(printf '%s\n' "${B_PROFILE_PKGS[@]}" | sort | uniq -d)"
  if [[ -n "$dupes" ]]; then
    t_fail "duplicate packages in $name: $dupes"
  fi
done
t_ok "every profile resolves with no duplicate packages"

b_profile_resolve gaming || t_fail "gaming did not resolve"
profile_has_flag multilib || t_fail "gaming must carry the !multilib flag"

b_profile_resolve full || t_fail "full did not resolve"
profile_has_flag multilib || t_fail "full must carry the !multilib flag"

b_profile_resolve minimal || t_fail "minimal did not resolve"
if profile_has_flag multilib; then
  t_fail "minimal must not need multilib"
fi
b_profile_resolve default || t_fail "default did not resolve"
if profile_has_flag multilib; then
  t_fail "default must not need multilib"
fi
t_ok "only gaming and full need multilib"

t_ok "profiles"
