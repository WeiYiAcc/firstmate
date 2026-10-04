#!/usr/bin/env bash
# Contract: the parsed Test step of .no-mistakes.yaml must drive the pi
# harness. test.instructions carries a machine-consumed enumeration mapping each
# harness an end user may start as a real primary to that harness's own launch
# command; this reads that enumeration as a name->command model and asserts the
# Test step offers pi and no longer offers claude. Prose elsewhere in the same
# block is not part of the model.
#
# Usage: fm-nm-test-harness-enumeration.test.sh [config-path]
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NM="${1:-$ROOT/.no-mistakes.yaml}"

# Normalized model: one "harness=launch-command" line per declared pair.
nm_test_harness_model() {
  python3 - "$1" <<'PY'
import re, sys, yaml

doc = yaml.safe_load(open(sys.argv[1])) or {}
instructions = str((doc.get("test") or {}).get("instructions") or "")
for name, command in re.findall(r"([A-Za-z0-9][\w.-]*)\s*->\s*`([^`]+)`", instructions):
    print(f"{name}={command.strip()}")
PY
}

test_test_step_drives_pi_harness() {
  command -v python3 >/dev/null 2>&1 \
    || fail "python3 is required to parse .no-mistakes.yaml for this contract"
  local model
  model=$(nm_test_harness_model "$NM") \
    || fail "failed to parse .no-mistakes.yaml as YAML"
  [ -n "$model" ] \
    || fail "test.instructions must map at least one harness to a launch command"
  local name command summary
  while IFS='=' read -r name command; do
    [ -n "$name" ] && [ -n "$command" ] \
      || fail "test.instructions maps harness '${name}' to an empty launch command"
  done <<<"$model"
  summary=$(tr '\n' ' ' <<<"$model")
  grep -qx 'pi=pi' <<<"$model" \
    || fail "test.instructions must drive the pi harness with 'pi'; got: $summary"
  ! grep -q '^claude=' <<<"$model" \
    || fail "test.instructions must not offer a claude harness scenario; got: $summary"
  pass "Test step drives pi and no longer drives claude: $summary"
}

test_test_step_drives_pi_harness