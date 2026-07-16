---
name: check-go-mistakes
description: Audits a Go project for common Go mistakes and anti-patterns. Use when the user asks to review/check/audit/fix a Go codebase for Go mistakes, anti-patterns, best-practice violations, or code smells - or to find bugs and improvement opportunities in Go code. Reports which mistakes were found, where, and how to fix them, respecting the project's Go version (mistakes already fixed by the language in newer releases are skipped). When asked to fix/repair, additionally applies the safe mechanically-fixable subset and verifies the build.
---

# Check a Go project for common Go mistakes

## Go version

!`grep -rhE "^go [0-9]+\.[0-9]+" --include="go.mod" . 2>/dev/null | awk '{print $2}' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}' | grep . || echo unknown`

Use ONLY the version above as the project's target Go version. If it shows `unknown`, ask the user which Go version to target before continuing.

## Mode

**Audit mode** (default) reports only. **Fix mode** - invoked as `/check-go-mistakes fix` or when the user asks to fix/repair - also applies Step 4. Steps 1–3 are the same in both.

## Steps

### 1. Skip version-gated mistakes

The language already fixed these, so skip them entirely: #32 and #63 (Go ≥ 1.22), #76 (Go ≥ 1.23), #100 (Go ≥ 1.25). Announce the detected version and which are skipped; do not list features or ask for confirmation - just proceed.

### 2. Run the first-pass scanner

```bash
bash <this skill's directory>/scripts/scan.sh "<detected-version>" .
```

Output is `#ID|severity|file:line|message [snippet]` (plus `#SCAN`/`#END` markers). It is a **candidate generator** - every line must be verified by reading the surrounding code; expect false positives and a few misses. It covers `#3, #13, #16, #17, #29, #35, #39, #48, #50, #51, #54, #62, #65, #71, #75, #76*, #79, #80, #81, #83, #86, #89, #100*` (`*` = version-gated). Group candidates by ID and confirm each is a real instance (not a false positive or comment).

### 3. Check the judgment-based mistakes

Most mistakes can't be detected by a single-line regex. `reference.md` (next to this file) holds every mistake as: **Applies to** (Go versions), **Detection**, **Why**, **Fix**. Look entries up by ID (e.g. `grep -n '#51'`) rather than reading the whole file, then scan representative packages (highest churn / `main` / handlers / concurrency) following each entry's **Detection** heuristic. Prioritize by impact:

- Concurrency: #58 data races, #62 goroutine lifetimes, #69/#70 shared slices/maps under mutexes, #74 copied `sync` types, #61 request ctx into a long-lived goroutine.
- Errors: #52 double-handling, #53/#54 dropped errors, #49 wrong wrap verb.
- Data types: #21/#27 un-preallocated slice/map, #26/#41 slicing/substring leaks, #18 integer overflow, #19 float `==`.
- Control: #30 range-copy mutation, #31 array-value range mutation, #33 map-order assumptions.
- Stdlib: #77 JSON, #78 SQL.
- API design: #42 receiver, #45 nil-receiver-as-interface, #46 filename input.
- Organization: #5/#6/#7 interface over-use, #15 undocumented exports.

### 4. Apply safe fixes (fix mode only)

**Skip in audit mode.** Apply only the whitelisted transforms below to **verified** findings - every other mistake stays report-only, even if `reference.md` has a Fix snippet:

| # | Transform |
|---|-----------|
| #17 octal literal | `010` -> `0o10`, `0755` -> `0o755` (prefix `0o`) |
| #51 error value compare | `err == ErrFoo` -> `errors.Is(err, ErrFoo)`; `err != ErrFoo` -> `!errors.Is(err, ErrFoo)` (add the `errors` import if missing) |

Do **not** auto-apply #50 (`err.(*T)` -> `errors.As`), #54 (`defer f.Close()`), #49 (`%v` -> `%w`), #23 (`== nil` -> `len == 0`), or #39 (`+=` -> `strings.Builder`) - they look mechanical but need judgment; report them with the Fix snippet. Then verify:

```bash
go build ./...
```

If the build fails because of a fix you applied, **revert that fix** and report it as "could not auto-fix (build failed)". Run `go vet ./...` and `go test ./...` where available.

### 5. Report

Produce a single markdown report:

1. **Header:** detected Go version, scope scanned, total findings by severity (`high`/`medium`/`low`), and (fix mode) how many were auto-fixed.
2. **Fixed automatically** (fix mode only): auto-fixed mistake IDs and `file:line` locations, the transform applied, and confirmation that `go build ./...` passed (or which fix was reverted).
3. **Findings**, grouped by mistake ID, most severe first. For each: `#NN - <title>` and chapter; severity; one or more `file:line` locations; **Why** (1–2 sentences from the reference); **Fix** with a short code snippet adapted to the actual code; a **Version note** when the fix relies on a Go feature (e.g. "≥ 1.21: use `maps.Clone`") or the mistake wouldn't apply on a newer Go version.
4. **Verified clean** (optional, brief): notable mistakes you specifically checked for and did not find.
5. **Skipped (version-gated):** the mistake IDs skipped in Step 1.

Cite only real `file:line` locations you actually read; do not invent locations. Drop scanner false positives (don't report them). For borderline cases, explain the trade-off and let the user decide.

## Notes

- The scanner is best-effort and regex-based; trust your reading over the scanner.
- Re-run `go vet`, `staticcheck`, and `golangci-lint` where available - #74 (copylocks), #15 (exported docs), #94 (field alignment) are exactly what those tools catch.
