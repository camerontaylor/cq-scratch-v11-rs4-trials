#!/usr/bin/env bash
# BASE-OWNED verifier. Runs from the default-branch checkout; never executes head code.
# inputs: HEAD_SHA, TRUST_REF (PR-immutable ref, e.g. origin/main), MEAS (untrusted artifact file)
set -uo pipefail
verdict=pass; reasons=()
fail(){ verdict=fail; reasons+=("$1"); }
cfg="$(git show "${TRUST_REF}:policy/ratchets.json")"
# 1. definition provenance: head may not change measurement definitions (D4/D11 -> needs-human)
for f in $(jq -r '.definitions[]' <<<"$cfg"); do
  b="$(git rev-parse -q --verify "${TRUST_REF}:$f" || echo none)"
  h="$(git rev-parse -q --verify "${HEAD_SHA}:$f" || echo none)"
  [ "$b" = "$h" ] || fail "definition changed: $f"
done
# 2. baseline guard, targets enumerated from TRUST_REF (A5: rename/new file is invisible to the target list)
for row in $(jq -c '.targets[]' <<<"$cfg"); do
  t="$(jq -r .target <<<"$row")"; p="$(jq -r .baseline <<<"$row")"
  bv="$(git show "${TRUST_REF}:$p" | jq -r .value)"
  hv="$(git show "${HEAD_SHA}:$p" 2>/dev/null | jq -r .value 2>/dev/null || echo missing)"
  if [ "$hv" = missing ] || [ -z "$hv" ]; then fail "baseline for $t missing at head"; 
  elif awk -v h="$hv" -v b="$bv" 'BEGIN{exit !(h<b)}'; then fail "baseline for $t loosened $bv -> $hv"; fi
  # 3. measurement: untrusted artifact, parsed as data only
  m="$(tr -d '[:space:]' < "$MEAS" 2>/dev/null || true)"
  if ! [[ "$m" =~ ^[0-9]{1,3}(\.[0-9])?$ ]]; then fail "measurement unparsable";
  elif awk -v m="$m" -v b="$bv" 'BEGIN{exit !(m<b)}'; then fail "$t measured $m < baseline $bv"; fi
done
# 4. unknown baseline files at head (A5 'adds a looser baseline') -> needs-human
for f in $(git ls-tree --name-only "${HEAD_SHA}" baselines/); do
  git cat-file -e "${TRUST_REF}:$f" 2>/dev/null || fail "new baseline file $f (needs-human)"
done
echo "verdict=$verdict"; printf 'reason: %s\n' "${reasons[@]}"
[ "$verdict" = pass ]
