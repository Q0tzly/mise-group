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

# --- enable-time version conflicts ---------------------------------------
# Separate groups dir and conf.d so the fixtures above stay as they are.
CG="$TMP/cgroups"
CC="$TMP/cconf.d"
mkdir -p "$CG"
cat > "$CG/aaa.toml" <<'EOF'
[tools]
jq = "1.8.0"
EOF
cat > "$CG/zzz.toml" <<'EOF'
[tools]
jq = "1.7.1"
EOF
cat > "$CG/twin.toml" <<'EOF'
[tools]
jq = "1.8.0"
EOF
cat > "$CG/tbl.toml" <<'EOF'
[tools]
"jq" = { version = "1.7.1", os = ["linux"] }
EOF
cat > "$CG/other.toml" <<'EOF'
[tools]
tool-x = "1"
EOF
cat > "$CG/bbb.toml" <<'EOF'
[tools]
jq = "1.9.0"
EOF

# conf_run <args...>: run mise-group against the conflict fixtures.
# Sets out (stdout), err (stderr), rc.
conf_run() {
  rm -f "$TMP/err"
  out="$(MISE_GROUPS_DIR="$CG" MISE_CONF_D="$CC" "$MG" "$@" 2>"$TMP/err")"
  rc=$?
  err="$(cat "$TMP/err")"
}
reset_conf() { rm -rf "$CC"; }

# conflict with an already enabled group: warned, enable still succeeds
reset_conf
conf_run enable --no-install aaa
conf_run enable --no-install zzz
check "conflict enable succeeds" "0" "$rc"
check "conflict enable still links" "yes" "$([[ -L "$CC/zzz.toml" ]] && echo yes || echo no)"
check_contains "conflict enable says enabled" "enabled zzz" "$out"
check "conflict warning line" \
  "warning: jq is pinned by aaa (1.8.0) and zzz (1.7.1); zzz wins (last file in conf.d)" "$err"

# same version on both sides: no warning
reset_conf
conf_run enable --no-install aaa
conf_run enable --no-install twin
check "same version succeeds" "0" "$rc"
check "same version no warning" "" "$err"

# two groups enabled together conflict with each other
reset_conf
conf_run enable --no-install aaa zzz
check "simultaneous enable succeeds" "0" "$rc"
check "simultaneous conflict warning" \
  "warning: jq is pinned by aaa (1.8.0) and zzz (1.7.1); zzz wins (last file in conf.d)" "$err"

# inline table form is compared by its version key
reset_conf
conf_run enable --no-install aaa
conf_run enable --no-install tbl
check "table form warning" \
  "warning: jq is pinned by aaa (1.8.0) and tbl (1.7.1); tbl wins (last file in conf.d)" "$err"

# no shared tool: no warning
reset_conf
conf_run enable --no-install aaa
conf_run enable --no-install other
check "no conflict no warning" "" "$err"

# two groups enabled earlier are not compared by a later enable
reset_conf
conf_run enable --no-install aaa
conf_run enable --no-install zzz
conf_run enable --no-install other
check "existing conflict not re-reported" "" "$err"

# three groups: each differing pin gets its own line against the winner
reset_conf
conf_run enable --no-install aaa
conf_run enable --no-install bbb zzz
check "three groups: one line per differing pin" "2" "$(grep -c '^warning: ' "$TMP/err")"
check_contains "three groups: aaa vs winner" \
  "warning: jq is pinned by aaa (1.8.0) and zzz (1.7.1); zzz wins" "$err"
check_contains "three groups: bbb vs winner" \
  "warning: jq is pinned by bbb (1.9.0) and zzz (1.7.1); zzz wins" "$err"

echo "---"
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
