---
name: check-go-mistakes
description: Audits a Go project for common Go mistakes and anti-patterns. Use when the user asks to review/check/audit/fix a Go codebase for Go mistakes, anti-patterns, best-practice violations, or code smells - or to find bugs and improvement opportunities in Go code. Reports which mistakes were found, where, and how to fix them, respecting the project's Go version (mistakes already fixed by the language in newer releases are skipped). When asked to fix/repair, additionally applies the safe mechanically-fixable subset and verifies the build.
---

# Check a Go project for common Go mistakes

## Detected Go version

!`grep -rhE "^go [0-9]+\.[0-9]+" --include="go.mod" . 2>/dev/null | awk '{print $2}' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}' | grep . || echo unknown`

Use ONLY the version shown above as the project's target Go version. If it shows
`unknown`, ask the user which Go version to target before continuing.

## How to run the check

The reference catalog and scanner script live next to this `SKILL.md`:

- `reference.md` - all mistakes; each entry has: **Applies to** (Go versions), **Detection**,
  **Why**, **Fix**.
- `scripts/scan.sh` - a fast first-pass candidate detector.

The skill runs in **audit mode** by default (report only). It is invoked as the
`/check-go-mistakes` command; pass `fix` (e.g. `/check-go-mistakes fix`) or otherwise ask
to **fix/repair** to also perform Step 4 and apply the safe fixes. Steps 1–3 are the same
in both modes.

### Step 1 - Confirm the version and which mistakes to skip

From the detected version, decide which version-gated mistakes to **skip** entirely (the
language already fixed them):

| Skip # | Mistake | When to skip |
|--------|---------|--------------|
| #32 | pointer elements in range loops | Go ≥ 1.22 |
| #63 | goroutines and loop variables | Go ≥ 1.22 |
| #76 | `time.After` memory leaks | Go ≥ 1.23 |
| #100 | Docker/Kubernetes GOMAXPROCS | Go ≥ 1.25 |

Announce the detected version and that these are skipped (if applicable). Do **not** list
features or ask for confirmation - just proceed.

### Step 2 - Run the automated first-pass scanner

Run the scanner against the project, passing the detected version so version-gated
checks are handled correctly:

```bash
bash <this skill's directory>/scripts/scan.sh "<detected-version>" .
```

The scanner prints lines of `#ID|severity|file:line|message [snippet]` (plus `#SCAN`/
`#END` markers). It is a **candidate generator** - every line must be verified by reading
the surrounding code; expect some false positives and a few misses. It covers the
mechanically-detectable subset:

`#3, #13, #16, #17, #29, #35, #39, #48, #50, #51, #54, #62, #65, #71, #75, #76*, #79,
#80, #81, #83, #86, #89, #100*`  (`*` = version-gated).

Parse the output, group candidates by mistake ID, and read each flagged location to
confirm it is a real instance (not a false positive or a comment).

### Step 3 - Check the judgment-based mistakes

Most mistakes can't be detected by a single-line regex - they need a human
reading the code. Look up entries in `reference.md` by mistake ID (e.g. `grep -n '#51'`)
rather than reading the whole file, and scan the codebase for
the high-value judgment mistakes. Prioritize, in rough order of impact:

- **Concurrency:** #58 data races (run/look for shared state without sync), #62
  goroutine lifetimes, #69/#70 shared slices/maps under mutexes, #74 copied `sync` types,
  #61 request-context leaked into long-lived goroutines.
- **Errors:** #52 double-handling (logged *and* returned), #53/#54 silently
  dropped errors, #49 wrong wrap verb.
- **Data types:** #21/#27 un-preallocated slices/maps, #26/#41 slicing/substring
  memory leaks, #18 integer overflows on untrusted input, #19 float `==`.
- **Control:** #30 mutating a range copy, #31 ranging an array value being
  mutated, #33 map-order assumptions.
- **Stdlib:** #77 JSON (embedded `time.Time`, monotonic clock, `float64` numbers),
  #78 SQL (no `Ping`, no pool config, `fmt.Sprintf` SQL, missing `rows.Err()`).
- **API design:** #42 wrong receiver, #45 returning a nil receiver as an
  interface, #46 filename-as-input.
- **Organization:** #5/#6/#7 interface over-use, #15 undocumented exports.

You don't need to read every file top-to-bottom - sample representative packages (the
ones with the most churn / the `main` / handlers / concurrency code) and follow the
**Detection** heuristic for each mistake from the reference file.

### Step 4 - Apply safe fixes (fix mode only)

**Skip this step in audit mode.** Only when the user asked to fix/repair, apply the
mechanically-safe fixes below to the **verified** findings from Step 2/3. These are
deterministic, single-spot transforms that are either purely cosmetic or strictly more
correct. Apply **only** to findings whose mistake ID is in this whitelist - every other
mistake stays report-only, even if the reference has a Fix snippet.

| # | Mistake | Transform |
|---|---------|-----------|
| #17 | octal literal | `010` -> `0o10`, `0755` -> `0o755` (prefix `0o`) |
| #51 | error value compare | `err == ErrFoo` -> `errors.Is(err, ErrFoo)`; `err != ErrFoo` -> `!errors.Is(err, ErrFoo)` (add the `errors` import if missing) |

Do **not** auto-apply any other mistake. In particular #50 (`err.(*T)` -> `errors.As`),
#54 (`defer f.Close()`), #49 (`%v` -> `%w`), #23 (`== nil` -> `len == 0`), and #39
(string `+=` -> `strings.Builder`) look mechanical but need judgment - report them with
the Fix snippet for the user to apply.

After applying, verify the project still builds:

```bash
go build ./...
```

If the build fails because of a fix you applied, **revert that fix** and report it as
"could not auto-fix (build failed)" instead. Run `go vet ./...` and the project's tests
(`go test ./...`) where available for extra confidence.

### Step 5 - Report

Produce a single markdown report. Structure:

1. **Header:** detected Go version, scope scanned, total findings by severity
   (`high`/`medium`/`low`), and (fix mode) how many were auto-fixed.
2. **Fixed automatically (fix mode only):** the mistake IDs and `file:line` locations
   auto-fixed from the whitelist, with a one-line note of the transform applied, and
   confirmation that `go build ./...` passed (or which fix was reverted).
3. **Findings**, grouped by mistake ID, most severe first. For each:
   - `#NN - <title>` and chapter.
   - Severity.
   - One or more `file:line` locations.
   - **Why** it's a mistake (1–2 sentences, from the reference).
   - **Fix** with a short code snippet (from the reference), adapted to the actual code.
   - A **Version note** when the fix relies on a Go feature (e.g. "≥ 1.21: use
     `maps.Clone`") or when the mistake would not apply on a newer Go version.
4. **Verified clean (optional, brief):** notable mistakes you specifically checked for and
   did not find, so the user knows the coverage.
5. **Skipped (version-gated):** list the mistake IDs skipped because the Go version is new
   enough (from Step 1), so it's clear they weren't silently ignored.

Be precise: cite real `file:line` locations you actually read, and only report a finding
if you verified it. Do not invent locations. If the scanner flagged something that turned
out to be a false positive, drop it (don't report it). If a candidate is borderline,
explain the trade-off and let the user decide.

## Notes

- The scanner is best-effort and regex-based; trust your reading over the scanner.
  Re-run `go vet`, `staticcheck`, and `golangci-lint` where available for corroboration -
  several mistakes (#74 copylocks, #15 exported docs, #94 field alignment) are exactly
  what those tools catch.
