#!/usr/bin/env bash
# Offline tests for bin/agy: uses a fake "real" binary that only prints what
# the wrapper sets. No network, no real CLI, no login.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$2] got [$3]"; fail=1; fi
}

mkdir -p "$T/real" "$T/wrap"
printf '#!/usr/bin/env bash\necho "HOME=$HOME CODEX_HOME=${CODEX_HOME:-unset} ARGS=$*"\n' > "$T/real/agy"
chmod +x "$T/real/agy"
cp "$ROOT/bin/agy" "$T/wrap/agy"
printf '%s\n' "$T/real/agy" > "$T/wrap/.agy-real-bin"
export HOME="$T/home"; mkdir -p "$HOME"
unset CODEX_HOME AGY_LOGIN_NEW_PROFILES_DIR CODEX_LOGIN_NEW_PROFILES_DIR

out="$("$T/wrap/agy" --login_new work models 2>/dev/null)"
check "agy sets HOME" "HOME=$HOME/.agy-profiles/work CODEX_HOME=unset ARGS=models" "$out"
out="$("$T/wrap/agy" --conversation abc 2>/dev/null)"
check "agy without flag is untouched" "HOME=$HOME CODEX_HOME=unset ARGS=--conversation abc" "$out"
out="$(AGY_LOGIN_NEW_PROFILES_DIR="$T/p" "$T/wrap/agy" --login_new=w a 2>/dev/null)"
check "env override + --login_new=" "HOME=$T/p/w CODEX_HOME=unset ARGS=a" "$out"

mkdir -p "$HOME/.agy-profiles/a/.gemini/antigravity-cli"; touch "$HOME/.agy-profiles/a/.gemini/antigravity-cli/antigravity-oauth-token"
mkdir -p "$HOME/.agy-profiles/b"
out="$("$T/wrap/agy" --login_new)"
check "list shows login state" "yes" "$(grep -q 'a  *logged in' <<<"$out" && grep -q 'b  *not logged in' <<<"$out" && echo yes)"

echo "[user]" > "$HOME/.gitconfig"; mkdir -p "$HOME/.ssh"; echo KEY > "$HOME/.ssh/id_x"
"$T/wrap/agy" --login_new sym models >/dev/null 2>&1
check ".gitconfig symlinked" "$HOME/.gitconfig" "$(readlink "$HOME/.agy-profiles/sym/.gitconfig")"
check ".ssh symlinked (not copied)" "$HOME/.ssh" "$(readlink "$HOME/.agy-profiles/sym/.ssh")"
mkdir -p "$HOME/.agy-profiles/own"; echo mine > "$HOME/.agy-profiles/own/.gitconfig"
"$T/wrap/agy" --login_new own models >/dev/null 2>&1
check "existing profile .gitconfig not overwritten" "mine" "$(cat "$HOME/.agy-profiles/own/.gitconfig")"
check "no symlink created over existing file" "" "$(readlink "$HOME/.agy-profiles/own/.gitconfig")"

"$T/wrap/agy" --login_new 'bad/name' >/dev/null 2>&1; check "invalid name rejected" "1" "$?"

# installer refuses to clobber a real regular-file binary at the target path
mkdir -p "$T/bin2"; cp "$T/real/agy" "$T/bin2/agy"
PATH="$T/bin2:$PATH" "$ROOT/install.sh" "$T/bin2" >/dev/null 2>&1; check "installer refuses to overwrite real binary" "1" "$?"
check "real binary intact" "yes" "$(grep -q 'ARGS=' "$T/bin2/agy" && echo yes)"
PATH="$T/bin2:$PATH" "$ROOT/install.sh" "$T/wrapdir" >/dev/null 2>&1; check "installer into separate dir" "0" "$?"
check "real-bin recorded" "$T/bin2/agy" "$(<"$T/wrapdir/.agy-real-bin")"
PATH="$T/bin2:$PATH" "$ROOT/install.sh" --uninstall "$T/wrapdir" >/dev/null 2>&1
check "uninstall removes wrapper" "no" "$([[ -e "$T/wrapdir/agy" ]] && echo yes || echo no)"

exit $fail
