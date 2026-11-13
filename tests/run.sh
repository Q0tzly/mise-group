#!/bin/bash
# Tests for the mise-group binary (built from cmd/mise-group). Uses a stub
# `mise` on PATH; the real mise and the real ~/.config/mise are never
# touched (MISE_GROUPS_DIR / MISE_CONF_D point at a temp dir).
# Run: tests/run.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MG="$TMP/mise-group"
(cd "$ROOT" && go build -o "$MG" ./cmd/mise-group) || { echo "build failed" >&2; exit 1; }

export MISE_GROUPS_DIR="$TMP/groups"
export MISE_CONF_D="$TMP/conf.d"
mkdir -p "$MISE_GROUPS_DIR" "$MISE_CONF_D" "$TMP/bin"

# --- stub mise -----------------------------------------------------------
# `mise install`            -> log the call
# `mise ls --json <tool>`   -> print a "source" for tools listed (one per
#                              line) in $TMP/still_used, {} otherwise
# `mise uninstall --all <t>`-> log the tool name
cat > "$TMP/bin/mise" <<EOF
#!/bin/bash
case "\$1" in
  install) echo install >> "$TMP/mise.log" ;;
  ls)
    tool="\${3:-}"
    if grep -qx "\$tool" "$TMP/still_used" 2>/dev/null; then
      echo '{"source":{"type":"mise.toml","path":"other.toml"}}'
    else
      echo '{}'
    fi
    ;;
  uninstall) echo "\${3:-}" >> "$TMP/uninstalled.log" ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/mise"
export PATH="$TMP/bin:$PATH"
: > "$TMP/still_used"

# --- fixtures ------------------------------------------------------------
cat > "$MISE_GROUPS_DIR/alpha.toml" <<'EOF'
[tools]
tool-a = "latest"
shared = "latest"
EOF
cat > "$MISE_GROUPS_DIR/beta.toml" <<'EOF'
[tools]
tool-b = "latest"
"cargo:some-crate" = "latest"
EOF

pass=0 fail=0
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    pass=$((pass+1)); echo "ok - $1"
  else
    fail=$((fail+1)); echo "FAIL - $1" >&2
    echo "  expected: $2" >&2; echo "  actual:   $3" >&2
  fi
}
check_contains() { # check_contains <name> <needle> <haystack>
  case "$3" in
    *"$2"*) pass=$((pass+1)); echo "ok - $1" ;;
    *) fail=$((fail+1)); echo "FAIL - $1: missing [$2] in [$3]" >&2 ;;
  esac
}

# names
check "names" "alpha beta" "$("$MG" names | tr '\n' ' ' | sed 's/ $//')"

# list shows both as disabled, with parsed tool names (quotes stripped)
out="$("$MG" list)"
check_contains "list alpha disabled" "[ ] alpha" "$out"
check_contains "list parses quoted tool" "cargo:some-crate" "$out"

# enable --no-install links but does not call mise install
out="$("$MG" enable --no-install alpha)"
check_contains "enable says enabled" "enabled alpha" "$out"
[[ -L "$MISE_CONF_D/alpha.toml" ]] && r=yes || r=no
check "enable creates conf.d link" "yes" "$r"
[[ -f "$TMP/mise.log" ]] && r=yes || r=no
check "enable --no-install skips install" "no" "$r"
out="$("$MG" list)"
check_contains "list alpha enabled" "[x] alpha" "$out"

# enable (with install) calls mise install once
"$MG" enable beta >/dev/null
check "enable calls mise install" "install" "$(cat "$TMP/mise.log")"

# unknown group: fails and changes nothing (validate-all-first)
"$MG" enable --no-install alpha nope 2>/dev/null && r=ok || r=error
check "enable unknown group fails" "error" "$r"

# disable: tools still used elsewhere are kept, the rest are uninstalled
echo "shared" > "$TMP/still_used"
out="$("$MG" disable alpha)"
check_contains "disable keeps shared tool" "keep shared" "$out"
check_contains "disable removes own tool" "removed tool-a" "$out"
check "uninstalled is tool-a only" "tool-a" "$(cat "$TMP/uninstalled.log")"
[[ -L "$MISE_CONF_D/alpha.toml" ]] && r=yes || r=no
check "disable removes conf.d link" "no" "$r"

# missing groups directory is a clear error, not a silent empty list
out="$(MISE_GROUPS_DIR="$TMP/nonexistent" "$MG" list 2>&1)" && r=ok || r=error
check "missing groups dir fails" "error" "$r"
check_contains "missing groups dir message" "no groups directory" "$out"

# version command works (value is "dev" outside release builds)
check_contains "version" "mise-group " "$("$MG" version)"

echo "---"
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
