# check-go-mistakes

A skill for code agents that audits a Go project for the **100 common Go mistakes** from
the book *"100 Go Mistakes and How to Avoid Them"* by Teiva Harsanyi (online summary:
<https://100go.co/>).

When the skill runs in a Go project, it:

1. **Detects the project's Go version** from `go.mod`.
2. **Scans the code** with a fast first-pass detector (`scripts/scan.sh`) that flags
   candidate locations for the mechanically-detectable mistakes.
3. **Reads the code** to verify each candidate and to check the judgment-based mistakes,
   using a built-in reference catalog of all mistakes (detection heuristic, why it's
   a mistake, and how to fix it).
4. **Reports** which mistakes were found, where (`file:line`), and how to fix them.
5. **Fixes** (when asked to fix) the safe, mechanically-fixable subset directly, then
   re-builds to verify; judgment-based mistakes are left for manual review.

## Version-aware

Some mistakes were fixed in the Go language itself and are **no longer mistakes** from a
certain version onward. The skill skips them based on the detected version:

| # | Mistake | Not a mistake from |
|---|---------|--------------------|
| #32 | pointer elements in range loops | Go 1.22 |
| #63 | goroutines and loop variables | Go 1.22 |
| #76 | `time.After` memory leaks | Go 1.23 |
| #100 | Docker/Kubernetes GOMAXPROCS | Go 1.25 |

Fixes that rely on newer standard-library features (e.g. `errors.Is`/`As` ≥ 1.13, `any`
≥ 1.18, `slices`/`maps` ≥ 1.21, `b.Loop()` ≥ 1.24) are annotated with the minimum version.

## Structure

```
.claude-plugin/plugin.json              # plugin manifest
skills/check-go-mistakes/
├── SKILL.md                            # skill entry point + workflow
├── scripts/scan.sh                     # fast grep/awk candidate detector
└── reference.md                        # knowledge base, all mistakes (#1–#100)
```

## Installation

Distributed as a [Claude Code](https://claude.com/claude-code) plugin. In a Claude Code
session, run:

```
/plugin marketplace add cxljs/check-go-mistakes
/plugin install check-go-mistakes
```

This auto-discovers the `skills/check-go-mistakes` skill and exposes the
`/check-go-mistakes` command. For other agents, the skill is a plain `SKILL.md` plus
scripts - copy `skills/check-go-mistakes/` into your agent's skills directory.

## Usage

The plugin adds the `/check-go-mistakes` command. Run it in any Go project:

```
/check-go-mistakes
```

The command detects the Go version from `go.mod`, runs the scanner, reads the code, and
produces a report grouped by mistake with locations and fixes.

To have it apply the safe fixes directly, pass `fix`:

```
/check-go-mistakes fix
```

In fix mode it also applies the small safe-fix whitelist (e.g. octal literals,
`errors.Is`) and re-builds to verify.

## Limitations

- The scanner is regex-based and best-effort; expect some false positives and misses.
  Verification by reading the code is part of the workflow.
- Judgment-based mistakes (concurrency design, interface over-use, project structure,
  optimization) require the agent to read representative parts of the codebase - they are
  not fully automated.
- Auto-fix covers only a small whitelist of mechanically-safe transforms (e.g. octal
  literals, `errors.Is`); judgment-based mistakes are reported with a fix snippet for
  manual review, not auto-applied.
