#!/usr/bin/env bash
#
# scan.sh - fast candidate detector for "100 Go Mistakes and How to Avoid Them"
#
# This is a FIRST-PASS scanner. It flags *candidate* locations using lightweight
# regex (and one awk brace-tracker for #35). Every line it emits is a CANDIDATE
# that must be verified by reading the surrounding code - expect some false
# positives and the occasional miss. It deliberately covers only mistakes that
# can be detected reliably from a single line (plus #35). The judgment-based
# mistakes are handled by the skill reading the reference docs.
#
# Usage:  scan.sh [GO_VERSION] [PROJECT_DIR]
#   GO_VERSION - e.g. "1.22" (taken from go.mod if omitted)
#   PROJECT_DIR - defaults to "."
#
# Output: lines of  ID|severity|file:line|message
# Exit:  0 always (findings are on stdout)
#
set -u

VERSION_ARG="${1:-}"
ROOT="${2:-.}"
cd "$ROOT" 2>/dev/null || { echo "#ERR|high|scan.sh|cannot cd to $ROOT"; exit 0; }

# ---------- Go version detection ----------
detect_version() {
    if [ -n "$VERSION_ARG" ]; then
        echo "$VERSION_ARG"; return
    fi
    local v
    v=$(grep -rhE '^go [0-9]+\.[0-9]+' --include='go.mod' . 2>/dev/null | head -1 | awk '{print $2}')
    [ -n "$v" ] && { echo "$v"; return; }
    echo "0.0"
}
GO_VER=$(detect_version)

# ver_lt <v> <ref>  -> 0 (true) if v < ref   (handles "major.minor" only)
ver_lt() {
    local v1 v2 r1 r2
    IFS=. read -r v1 v2 _ <<< "$1"
    IFS=. read -r r1 r2 _ <<< "$2"
    v1=${v1:-0}; v2=${v2:-0}; r1=${r1:-0}; r2=${r2:-0}
    [ "$v1" -lt "$r1" ] && return 0
    [ "$v1" -gt "$r1" ] && return 1
    [ "$v2" -lt "$r2" ] && return 0
    return 1
}

# ---------- helpers ----------
GO_FILES_OPTS=(--include='*.go' --exclude-dir=vendor --exclude-dir=.git --exclude-dir=node_modules -rnE)

# emit_matches <id> <severity> <message> <grep_pattern> [grep extra files...]
emit_matches() {
    local id="$1" sev="$2" msg="$3" pat="$4"; shift 4
    grep "${GO_FILES_OPTS[@]}" -- "$pat" "${@:-.}" 2>/dev/null | while IFS= read -r line; do
        [ -z "$line" ] && continue
        local f rest l snippet
        f="${line%%:*}"; rest="${line#*:}"; l="${rest%%:*}"; snippet="${rest#*:}"
        # trim leading whitespace
        snippet="${snippet#"${snippet%%[![:space:]]*}"}"
        # skip full-line comments
        case "$snippet" in //*) continue ;; esac
        case "$snippet" in /*\ *) continue ;; esac
        printf '%s|%s|%s:%s|%s  [%s]\n' "$id" "$sev" "$f" "$l" "$msg" "$snippet"
    done
}

emit_one() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }

# ---------- header ----------
echo "#SCAN go-version=$GO_VER root=$ROOT"

# ---------- #3  init functions ----------
emit_matches "#03" "medium" "init() limits error handling & complicates testing; prefer an explicit init function called from main" '^[[:space:]]*func init\(\)'

# ---------- #13  utility packages ----------
while IFS= read -r d; do
    [ -z "$d" ] && continue
    emit_one "#13" "medium" "$d/" "utility-style package name (util/common/shared/helpers/misc); rename after what it provides"
done < <(find . -type d \( -name util -o -name utils -o -name common -o -name shared -o -name helpers -o -name misc \) \
    -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null)

# ---------- #16  no golangci-lint config ----------
if ! find . -maxdepth 3 \( -name '.golangci.yml' -o -name '.golangci.yaml' -o -name '.golangci.toml' \) \
    -not -path '*/vendor/*' 2>/dev/null | grep -q .; then
    emit_one "#16" "low" "$ROOT/(root)" "no golangci-lint config found; adopt golangci-lint + gofmt/goimports in CI"
fi

# ---------- #17  octal literals (0-prefixed, not 0x/0b/0o) ----------
emit_matches "#17" "medium" "integer literal starting with 0 is octal; make it explicit with 0o (e.g. 0o755)" '\b0[0-7]+\b'

# ---------- #29  reflect.DeepEqual (review hot paths) ----------
emit_matches "#29" "low" "reflect.DeepEqual is slow; prefer == / bytes.Equal / slices.Equal / maps.Equal where possible" 'reflect\.DeepEqual'

# ---------- #39  string concatenation with += ----------
emit_matches "#39" "medium" "string += in a loop is O(n^2); use strings.Builder (and Grow if length known)" '\+= *("|\x60)'

# ---------- #48  panic ----------
emit_matches "#48" "medium" "panic stops the goroutine; return an error unless truly unrecoverable" '\bpanic\('

# ---------- #50  error type assertion (use errors.As) ----------
emit_matches "#50" "medium" "error type assertion misses wrapped errors; use errors.As(err, &target)" '\berr[[:space:]]*\.[[:space:]]*\('

# ---------- #51  error value comparison (use errors.Is) ----------
grep "${GO_FILES_OPTS[@]}" -- '\berr[[:space:]]*(==|!=)[[:space:]]*\S' . 2>/dev/null \
    | grep -vE '\berr[[:space:]]*(==|!=)[[:space:]]*nil\b' \
    | while IFS= read -r line; do
        f="${line%%:*}"; rest="${line#*:}"; l="${rest%%:*}"; snippet="${rest#*:}"
        snippet="${snippet#"${snippet%%[![:space:]]*}"}"
        printf '#51|medium|%s:%s|compare errors with errors.Is, not == / != (misses wrapped errors)  [%s]\n' "$f" "$l" "$snippet"
    done

# ---------- #54  defer ignoring error (Close/Decode/Sync) ----------
emit_matches "#54" "medium" "defer discards an error; handle it, propagate it, or make the drop explicit with _ =" 'defer[[:space:]]+.*\.(Close|Decode|Sync|Flush)\('

# ---------- #62  goroutine launches (lifecycle review) ----------
emit_matches "#62" "low" "goroutine started - confirm there is a plan to stop it (ctx/cancel/WaitGroup) to avoid a leak" '^[[:space:]]*go[[:space:]]+(func|\w)'

# ---------- #65  chan bool notification ----------
emit_matches "#65" "low" "notification channel should be chan struct{}, not chan bool" 'chan[[:space:]]+bool'

# ---------- #71  wg.Add placement review ----------
emit_matches "#71" "medium" "verify wg.Add is called BEFORE the goroutine starts, not inside it" 'wg\.Add\('

# ---------- #75  bare numeric time.Duration ----------
emit_matches "#75" "high" "time.Duration is in nanoseconds; a bare int is almost certainly wrong - use time.Second / time.Millisecond etc." 'time\.(NewTicker|Tick|After|AfterFunc|Sleep|NewTimer)\(\s*[0-9]+\s*\)'

# ---------- #76  time.After in loops (Go < 1.23 only) ----------
if ver_lt "$GO_VER" "1.23"; then
    emit_matches "#76" "medium" "time.After leaks a timer until it fires; in a select loop use time.NewTimer + Stop (Go < 1.23)" 'time\.After\('
fi

# ---------- #79  transient resources not closed ----------
emit_matches "#79" "medium" "resource opened - verify a defer Close (resp.Body / rows / file)" '(http\.(Get|Post|Head|PostForm)\(|\.Do\(|os\.(Open|Create|OpenFile)\(|\.Query\(|\.QueryContext\()'

# ---------- #80  http.Error without return ----------
emit_matches "#80" "high" "http.Error does not stop the handler; add a return after it" 'http\.Error\('

# ---------- #81  default HTTP client / server (no timeouts) ----------
emit_matches "#81" "medium" "default/HTTP-client/server has no timeouts; configure a custom client.Timeout and server Read/Write/Idle timeouts" '(http\.(Get|Post|Head|PostForm)\(|http\.DefaultClient|http\.DefaultTransport|http\.ListenAndServe\(|http\.Server\{)'

# ---------- #86  time.Sleep in tests ----------
grep "${GO_FILES_OPTS[@]}" -- 'time\.Sleep' . 2>/dev/null | grep -E '_test\.go:' | while IFS= read -r line; do
    f="${line%%:*}"; rest="${line#*:}"; l="${rest%%:*}"; snippet="${rest#*:}"
    snippet="${snippet#"${snippet%%[![:space:]]*}"}"
    printf '#86|medium|%s:%s|avoid time.Sleep in tests; synchronize on a signal or use an eventually/retry helper  [%s]\n' "$f" "$l" "$snippet"
done

# ---------- #89  benchmark b.N loop (use b.Loop() on >= 1.24) ----------
grep "${GO_FILES_OPTS[@]}" -- '<[[:space:]]*b\.N' . 2>/dev/null | grep -E '_test\.go:' | while IFS= read -r line; do
    f="${line%%:*}"; rest="${line#*:}"; l="${rest%%:*}"; snippet="${rest#*:}"
    snippet="${snippet#"${snippet%%[![:space:]]*}"}"
    printf '#89|low|%s:%s|use b.Loop() (Go 1.24+) instead of for i:=0; i<b.N; i++; ensure a side effect so the compiler cannot eliminate the work  [%s]\n' "$f" "$l" "$snippet"
done

# ---------- #83  race flag in CI/scripts ----------
ci_files=$(find . -maxdepth 4 \( -name 'Makefile' -o -name '*.mk' -o -path '*/.github/workflows/*' -name '*.yml' -o -path '*/.github/workflows/*' -name '*.yaml' -o -name '.gitlab-ci.yml' -o -path '*/scripts/*' \) \
    -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null)
if [ -n "$ci_files" ] && ! echo "$ci_files" | xargs grep -lE '(^|[^-])--?race\b|-race' 2>/dev/null | grep -q .; then
    emit_one "#83" "low" "$ROOT/(ci)" "no -race flag found in CI/Makefile/scripts; run go test -race ./... for concurrent code"
fi

# ---------- #35  defer inside a for/range loop (awk brace-tracker) ----------
awk '
function strip(s,   out,i,n,c,nx,ins,inr,inc,inb) {
    out=""; n=length(s); ins=0; inr=0; inc=0; inb=0; i=1
    while (i<=n) {
        c=substr(s,i,1); nx=substr(s,i+1,1)
        if (inb) { if (c=="*"&&nx=="/"){inb=0;i+=2;continue}; i++; continue }
        if (ins) { if (c=="\\"){out=out "  ";i+=2;continue}; if (c=="\""){ins=0;out=out " ";i++;continue}; out=out " "; i++; continue }
        if (inr) { if (c=="`"){inr=0;out=out " ";i++;continue}; out=out " "; i++; continue }
        if (inc) { if (c=="\\"){out=out "  ";i+=2;continue}; if (c=="\x27"){inc=0;out=out " ";i++;continue}; out=out " "; i++; continue }
        if (c=="/"&&nx=="/") { break }
        if (c=="/"&&nx=="*") { inb=1; i+=2; continue }
        if (c=="\"") { ins=1; out=out " "; i++; continue }
        if (c=="`")  { inr=1; out=out " "; i++; continue }
        if (c=="\x27"){ inc=1; out=out " "; i++; continue }
        out=out c; i++
    }
    return out
}
FNR==1 { depth=0; for (d in stack) delete stack[d]; lookback="" }
{
    s=strip($0)
    gsub(/[{}]/, " & ", s)
    gsub(/[ \t]+/, " ", s)
    nt=split(s, arr, " ")
    for (k=1;k<=nt;k++) {
        t=arr[k]
        if (t=="") continue
        if (t=="{") {
            opener="other"
            if (lookback ~ /(^| )for( |$)/) opener="for"
            else if (lookback ~ /(^| )range( |$)/) opener="range"
            else if (lookback ~ /(^| )func( |$)/) opener="func"
            else if (lookback ~ /(^| )if( |$)/) opener="if"
            else if (lookback ~ /(^| )switch( |$)/) opener="switch"
            else if (lookback ~ /(^| )select( |$)/) opener="select"
            stack[depth]=opener; depth++
            lookback=""; continue
        }
        if (t=="}") { if (depth>0){depth--; delete stack[depth]}; lookback=""; continue }
        if (t=="defer") {
            inloop=0
            for (d=depth-1; d>=0; d--) {
                if (stack[d]=="func") break
                if (stack[d]=="for"||stack[d]=="range") { inloop=1; break }
            }
            if (inloop) printf "#35|high|%s:%d|defer inside a for/range loop - it runs at function return, not per iteration (leak)\n", FILENAME, FNR
        }
        lookback = (lookback=="") ? t : lookback " " t
        # keep only the last 14 tokens so a `for`/`func` keyword near a `{` stays visible
        m=split(lookback, lb, " ")
        if (m > 14) {
            lookback=""
            for (z=m-13; z<=m; z++) lookback = (lookback=="") ? lb[z] : lookback " " lb[z]
        }
    }
}' $(find . -name '*.go' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null)

# ---------- #100  container GOMAXPROCS (Go < 1.25 only) ----------
if ver_lt "$GO_VER" "1.25"; then
    has_container=$(find . -maxdepth 4 \( -iname 'Dockerfile*' -o -iname '*.yaml' -o -iname '*.yml' \) \
        -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null | head -1)
    if [ -n "$has_container" ]; then
        if ! grep -rliE 'automaxprocs|GOMAXPROCS' . --include='*.go' --include='Dockerfile*' --include='*.yaml' --include='*.yml' 2>/dev/null | grep -q .; then
            emit_one "#100" "medium" "$ROOT/(containers)" "Go < 1.25 ignores cgroup CPU limits for GOMAXPROCS; set GOMAXPROCS or use go.uber.org/automaxprocs in containers"
        fi
    fi
fi

echo "#END"
