# Go Mistakes Reference

Each entry has: **Applies to** (Go versions), **Detection**, **Why**, **Fix**. Mistake IDs
run #1–#100.

## #1 — Unintended variable shadowing
- **Applies to:** all versions.
- **Detection (judgment):** an inner block redeclares a name from an outer scope
  (`err` is the classic case). `go vet -shadow` / `shadow` linter flags it. Look for
  `:=` inside `if`/`for`/`switch`/closures that rebinds an outer variable.
- **Why:** the code compiles, but the variable that receives the value may not be the one
  you expect — a common source of silent bugs.
- **Fix:** rename the inner variable, or reuse `=` instead of `:=` where you intend to
  assign the outer variable.
```go
// Buggy: the outer err is never set
var err error
if cond {
    err, val := doSomething() // shadows outer err
    _ = val
}
return err // always nil
// Fix: rename or assign explicitly
```

## #2 — Unnecessary nested code
- **Applies to:** all versions.
- **Detection (judgment):** deep nesting; `else` after a guarded `return`; happy path
  pushed to the right. `gocyclo`/`gocognit` flag high complexity.
- **Why:** the more nesting, the harder to build a mental model.
- **Fix:** guard clauses / early returns; align the happy path on the left; omit `else`
  when the `if` block returns.
```go
// Instead of:
if s != "" { /* happy */ } else { return errors.New("empty") }
// Flip the condition:
if s == "" { return errors.New("empty") }
/* happy path */
```

## #3 — Misusing init functions
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `func init()`.
- **Why:** `init` has limited error handling, forces global state, and complicates
  testing.
- **Fix:** handle initialization in an explicit function called from `main`. Reserve
  `init` for static config (e.g. registering a driver) where it can't fail meaningfully.

## #4 — Overusing getters and setters
- **Applies to:** all versions.
- **Detection (judgment):** exported `Get*`/`Set*` methods wrapping unexported fields with
  no added logic.
- **Why:** Go has no built-in getters/setters and they aren't idiomatic; blind use adds
  boilerplate.
- **Fix:** access fields directly unless you need encapsulation or forward compatibility.
  (Go idiom: a getter for `firstName` is `FirstName()`, not `GetFirstName()`.)

## #5 — Interface pollution
- **Applies to:** all versions.
- **Detection (judgment):** interfaces defined "just in case" on the producer side,
  single-implementation interfaces, or interfaces in the package that *defines* the type.
- **Why:** abstractions should be discovered, not created prematurely — they add
  complexity.
- **Fix:** create an interface only when you have multiple implementations or a concrete
  consumer need. Keep interfaces on the consumer side and minimal.

## #6 — Interface on the producer side
- **Applies to:** all versions.
- **Detection (judgment):** a package exports an interface that clients must depend on,
  when a concrete type would do.
- **Why:** the producer shouldn't force an abstraction on all clients.
- **Fix:** return concrete types; let consumers define the interface they need (implicitly
  satisfied). Exception: when you *know* an abstraction helps consumers, keep it minimal.

## #7 — Returning interfaces
- **Applies to:** all versions.
- **Detection (judgment):** a function/method whose return type is an interface.
- **Why:** restricts flexibility and couples all clients to one abstraction.
- **Fix:** return concrete implementations; accept interfaces. Return an interface only
  when you *know* clients need the abstraction.

## #8 — `any` says nothing
- **Applies to:** `any`/`interface{}` (≥ Go 1.18; `interface{}` before).
- **Detection (judgment):** `any` (or `interface{}`) used as a parameter/return/field type
  outside genuine "any value" cases (e.g. `json.Marshal`, `fmt.Print`).
- **Why:** `any` carries no information and lets callers pass anything, defeating
  compile-time checks.
- **Fix:** use a concrete type, a type parameter, or a small explicit interface. Prefer
  `any` over `interface{}` spelling on ≥ 1.18.

## #9 — Being confused about when to use generics
- **Applies to:** ≥ Go 1.18.
- **Detection (judgment):** type parameters used "to be generic" with no concrete need, or
  the opposite — copy-pasted boilerplate a type parameter would remove.
- **Why:** premature generics add abstraction/complexity; but where there's real need they
  remove boilerplate.
- **Fix:** use type parameters only when you see a concrete need (multiple types sharing
  identical logic).

## #10 — Not being aware of type embedding issues
- **Applies to:** all versions.
- **Detection (judgment):** an embedded type that promotes fields/methods that should stay
  hidden (e.g. embedding a `sync.Mutex` exposes `Lock`/`Unlock` to clients).
- **Why:** embedding promotes everything; you can accidentally expose internals.
- **Fix:** use a named field (`mu sync.Mutex`) instead of embedding when you don't want
  promotion. Don't embed solely as syntax sugar for field access.

## #11 — Not using the functional options pattern
- **Applies to:** all versions.
- **Detection (judgment):** constructors with many parameters, a config struct with many
  fields, or a builder that's awkward for error handling.
- **Why:** functional options give an API-friendly, extensible way to configure.
- **Fix:**
```go
type Option func(*options) error
func WithPort(p int) Option { return func(o *options) error { /* validate */ ; o.port = p; return nil } }
func NewServer(addr string, opts ...Option) (*Server, error) { /* apply opts */ }
```

## #12 — Project misorganization (structure & packages)
- **Applies to:** all versions.
- **Detection (judgment):** dozens of nano-packages (1–2 files), huge packages, packages
  named after contents not behavior, over-exporting.
- **Why:** hurts maintainability and readability.
- **Fix:** evolve structure as the project grows; name packages after what they *provide*;
  keep packages focused; minimize exports. See <https://go.dev/doc/modules/layout>.

## #13 — Creating utility packages
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags packages/dirs named `util`, `common`, `shared`, `helpers`,
  `misc`.
- **Why:** names like `common`/`util` convey nothing; they become dumping grounds.
- **Fix:** rename to a specific, behavior-describing package name (e.g. `httputil` → still
  generic; prefer the concrete domain).

## #14 — Ignoring package name collisions
- **Applies to:** all versions.
- **Detection (judgment):** a variable named the same as an imported package, preventing
  its use.
- **Why:** leads to confusion and bugs.
- **Fix:** rename the variable, or use an import alias.

## #15 — Missing code documentation
- **Applies to:** all versions.
- **Detection (judgment):** exported identifiers without a doc comment; packages without a
  `// Package ...` comment. `revive`'s `exported` rule and `golint` flag this.
- **Why:** undocumented exports hurt consumers and maintainers.
- **Fix:** document every exported element; comments start with the element's name and are
  full sentences; document each package with `// Package <name> ...`.

## #16 — Not using linters
- **Applies to:** all versions.
- **Detection:** `scan.sh` checks for a `golangci-lint` config (`.golangci.yml`/`.yaml`/
  `.toml`) and for `gofmt`/`goimports`/`go vet` usage in CI.
- **Why:** linters/formatters catch errors and enforce consistency automatically.
- **Fix:** adopt `golangci-lint` (bundles `errcheck`, `govet`, `staticcheck`, `gocyclo`,
  `goconst`, …) and run `gofmt`/`goimports`; automate in CI / pre-commit.

## #17 - Creating confusion with octal literals
- **Applies to:** all versions (the `0o` prefix is ≥ Go 1.13).
- **Detection:** `scan.sh` flags integer literals beginning with `0` followed by a digit
  (e.g. `010`, `0755`) that are *not* `0x`/`0b`/`0o`/`0X`/`0B`/`0O`.
- **Why:** `010` is octal (= 8), which surprises readers; `010` and `10` look similar but
  differ.
- **Fix:** make octal explicit with the `0o` prefix: `0o10`, `0o755`. Prefer underscores
  for readability (`1_000_000`).

## #18 - Neglecting integer overflows
- **Applies to:** all versions.
- **Detection (judgment):** arithmetic on user-controlled/sized integers without overflow
  checks (counters, sums, `a*b`, `len+ n`).
- **Why:** Go silently wraps on runtime overflow; compile-time overflow is a *compile*
  error, but runtime overflow is silent and can flip signs.
- **Fix:** add explicit overflow checks for untrusted inputs:
```go
func add(a, b int) (int, bool) {
    if (b > 0 && a > math.MaxInt-b) || (b < 0 && a < math.MinInt-b) {
        return 0, false
    }
    return a + b, true
}
// For constants: math.MaxInt32 + 1 is a compile error (good).
```

## #19 - Not understanding floating-points
- **Applies to:** all versions.
- **Detection (judgment):** direct `==`/`!=` comparisons of `float32`/`float64`; adding
  values of very different magnitudes.
- **Why:** floats are approximations; `1.0001*1.0001` may print `1.0002`, not
  `1.00020001`.
- **Fix:** compare within an epsilon; group same-magnitude operations; do
  multiply/divide before add/subtract.
```go
const eps = 1e-9
func almostEqual(a, b float64) bool { return math.Abs(a-b) < eps }
```

## #20 - Not understanding slice length and capacity
- **Applies to:** all versions.
- **Detection (judgment):** confusion between `len` (elements present) and `cap` (backing
  array size); misusing `make([]T, n)` vs `make([]T, 0, n)`.
- **Why:** misunderstanding leads to allocation surprises and bugs.
- **Fix:** `len` = number of available elements; `cap` = backing array size.
  `make([]T, n)` returns a length-n slice (zeroed); `make([]T, 0, n)` returns length 0,
  capacity n (use with `append`).

## #21 - Inefficient slice initialization
- **Applies to:** all versions.
- **Detection (judgment):** a slice built with `var s []T` + `append` in a loop when the
  final size is known, or `make([]T, 0)` without a capacity.
- **Why:** repeated growth copies the backing array and stresses the GC.
- **Fix:** preallocate. `make([]T, 0, n)` + `append`, or `make([]T, n)` + index assignment
  (slightly faster).
```go
s := make([]Foo, 0, len(items))
for _, it := range items { s = append(s, process(it)) }
```

## #22 - Being confused about nil vs. empty slice
- **Applies to:** all versions.
- **Detection (judgment):** `[]T{}` used to mean "no elements" where `var s []T` (nil) is
  clearer; or code that distinguishes nil from empty when it shouldn't (or fails to, e.g.
  with `encoding/json` where nil serializes to `null`, empty to `[]`).
- **Why:** nil and empty slices differ in allocation and JSON/reflect behavior.
- **Fix:** `var s []T` when unsure of final length / may be empty; `make([]T, n)` when
  length known; avoid `[]T{}` for empty init. Don't design APIs that distinguish nil from
  empty.

## #23 - Not properly checking if a slice is empty
- **Applies to:** all versions (same for maps).
- **Detection (judgment):** `if s == nil` / `if m == nil` used as an emptiness test instead
  of `len`. (Not auto-detected: too many false positives vs. the legitimate `err != nil`
  idiom. Grep `== nil`/`!= nil` and review slice/map variables by hand.)
- **Why:** checking `nil` misses the empty case; `len(s) == 0` covers both.
- **Fix:** check `len(s) == 0` / `len(m) == 0`.

## #24 - Not making slice copies correctly
- **Applies to:** all versions.
- **Detection (judgment):** misuse of `copy(dst, src)` where `dst` has zero length.
- **Why:** `copy` copies `min(len(dst), len(src))` elements; a zero-length destination
  copies nothing.
- **Fix:** ensure the destination has length (not just capacity):
```go
dst := make([]int, len(src))
copy(dst, src)
// or, ≥ Go 1.21: dst := slices.Clone(src)
```

## #25 - Unexpected side effects using slice append
- **Applies to:** all versions.
- **Detection (judgment):** slicing a slice (`s[:n]`) then `append`ing when `n < cap`,
  sharing a backing array across functions.
- **Why:** if the result's length < capacity, `append` can mutate the original slice.
- **Fix:** use a full slice expression `s[low:high:max]` to cap capacity, or `copy` /
  `slices.Clone` (≥ 1.21).

## #26 - Slices and memory leaks
- **Applies to:** all versions.
- **Detection (judgment):** slicing a large slice/array to keep a few elements (keeps the
  whole backing array alive); a `[]*T` / slice of structs-with-pointers where dropped
  tail elements keep referenced objects alive.
- **Why:** the GC won't reclaim the unreferenced backing-array space, or the pointed-to
  objects.
- **Fix:** copy to a new slice (`slices.Clone`) when shrinking. For pointer slices, nil
  out dropped elements before truncating: `s[i] = nil; s = s[:i]`.

## #27 - Inefficient map initialization
- **Applies to:** all versions.
- **Detection (judgment):** `make(map[K]V)` populated with a known number of entries in a
  loop.
- **Why:** map growth is expensive (rehash + rebucket).
- **Fix:** `make(map[K]V, n)` with the expected size.

## #28 - Maps and memory leaks
- **Applies to:** all versions.
- **Detection (judgment):** a map that grows large then has entries deleted but is expected
  to shrink.
- **Why:** a map can grow but never shrinks - deleted entries' buckets aren't freed.
- **Fix:** periodically recreate the map (`m = make(...)`) after bulk deletes, or store
  pointers (`map[K]*V`) so only small pointer values are held.

## #29 - Comparing values incorrectly
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `reflect.DeepEqual` (review for hot paths); judgment for
  `==` on non-comparable types.
- **Why:** `==` works only for comparable types (bool, numeric, string, pointer, channel,
  array/struct of comparables). Slices/maps/functions are not comparable. `reflect.DeepEqual`
  is correct but slow.
- **Fix:** use `==` for comparable types; use `bytes.Compare`/`bytes.Equal` for `[]byte`;
  write a custom comparison or use `cmp`/`maps.Equal`/`slices.Equal` (≥ 1.21) instead of
  reflection where performance matters.

## #30 - Ignoring that elements are copied in range loops
- **Applies to:** all versions.
- **Detection (judgment):** `for _, v := range s` where `v` is a struct (or has struct
  fields) and the loop mutates `v` expecting to change `s`.
- **Why:** the range value is a *copy*; mutating it doesn't affect the slice element
  (unless the element/field is a pointer).
- **Fix:** mutate via index:
```go
for i := range s { s[i].field = x }      // range over index
for i := 0; i < len(s); i++ { s[i].field = x } // classic loop
```

## #31 - Ignoring how arguments are evaluated in range loops (channels and arrays)
- **Applies to:** all versions.
- **Detection (judgment):** ranging over an array (value, not pointer) that is mutated
  during the loop, or expecting a channel expression to be re-evaluated each iteration.
- **Why:** the range expression is evaluated *once* before the loop (a copy is made), so
  mid-loop mutations of an array value aren't seen.
- **Fix:** range over a pointer to the array (`for i := range &a`), or a slice header
  (which shares the backing array).

## #32 - Ignoring the impacts of using pointer elements in range loops
- **Applies to:** **only Go < 1.22.** *Not a mistake from Go 1.22* (loop variables are
  per-iteration, so capturing them is safe).
- **Detection (judgment, Go < 1.22 only):** `for i, v := range` where `i`/`v` (or `for i
  := 0` classic loop vars) are captured by a goroutine/closure.
- **Why:** pre-1.22, the loop variable is reused across iterations, so closures capture the
  *same* variable - all goroutines see the last value.
- **Fix (Go < 1.22):** shadow the variable inside the loop:
```go
for _, v := range items {
    v := v // capture a fresh copy
    go process(v)
}
```

## #33 - Making wrong assumptions during map iterations
- **Applies to:** all versions.
- **Detection (judgment):** code relying on map iteration order, insertion order, or
  assuming an element inserted during iteration will be visited.
- **Why:** maps are unordered and have non-deterministic iteration; insertion-during-
  iteration behavior is unspecified.
- **Fix:** sort keys explicitly (`slices.Sorted(maps.Keys(m))` ≥ 1.23) if order matters;
  never rely on map ordering.

## #34 - Ignoring how the break statement works
- **Applies to:** all versions.
- **Detection (judgment):** a `break` inside a `switch`/`select` that is nested in a `for`.
  Grep `break` and check the surrounding construct.
- **Why:** `break` terminates the innermost `for`/`switch`/`select`. Inside a `switch`
  within a loop, `break` exits the *switch*, not the loop - a common surprise.
- **Fix:** use a label to break the intended statement:
```go
loop:
    for i := 0; i < 5; i++ {
        switch i {
        case 2:
            break loop // breaks the for, not the switch
        }
    }
```

## #35 - Using defer inside a loop
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `defer` lexically inside a `for` loop.
- **Why:** `defer` runs when the *surrounding function* returns, not per iteration - so
  resources pile up (file descriptors, memory) until the function exits.
- **Fix:** extract the loop body into a function so `defer` runs each iteration, or close
  explicitly:
```go
for path := range ch {
    if err := readFile(path); err != nil { return err }
}
func readFile(path string) error {
    f, err := os.Open(path); if err != nil { return err }
    defer f.Close()
    // ...
}
```

## #36 - Not understanding the concept of rune
- **Applies to:** all versions.
- **Detection (judgment):** using `len(s)` to count "characters"; treating `s[i]` as a
  character.
- **Why:** a Go string is a byte slice; `len` returns bytes, not runes. A rune is a Unicode
  code point (1–4 UTF-8 bytes). `len("hêllo")` is 6, not 5.
- **Fix:** count runes with `utf8.RuneCountInString(s)` or `len([]rune(s))`; iterate runes
  with `for i, r := range s`.

## #37 - Inaccurate string iteration
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `for i := range s` (or `for i, _ := range s`) combined with
  `s[i]` used as a rune/character - the index is a *byte* offset, not a rune index.
- **Why:** ranging a string yields byte offsets; `s[i]` is a byte, not the i-th rune.
  Printing `s[i]` for `hêllo` yields `hÃllo`.
- **Fix:** use the rune value from range: `for i, r := range s { ... r ... }`. To get the
  i-th rune by index, convert: `[]rune(s)[i]`.

## #38 - Misusing trim functions
- **Applies to:** all versions.
- **Detection (judgment):** `strings.TrimRight`/`TrimLeft` used when `TrimSuffix`/
  `TrimPrefix` was meant.
- **Why:** `TrimRight(s, "xo")` strips *all trailing runes in the set* {x,o}; `TrimSuffix`
  strips one exact suffix. `TrimRight("123oxo", "xo")` -> `123`; it would also strip
  `"123ox"` -> `123`.
- **Fix:** use `TrimPrefix`/`TrimSuffix` for a single fixed prefix/suffix; `TrimLeft`/
  `TrimRight` for a set of runes.

## #39 - Under-optimized strings concatenation
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `+=` on a string variable inside a loop (building a string
  by concatenation).
- **Why:** strings are immutable; `s += v` reallocates each iteration - O(n²).
- **Fix:** use `strings.Builder`, and `Grow` if the total length is known:
```go
var sb strings.Builder
total := 0; for _, v := range values { total += len(v) }
sb.Grow(total)
for _, v := range values { sb.WriteString(v) }
return sb.String()
```

## #40 - Useless string conversions
- **Applies to:** all versions.
- **Detection (judgment):** repeated `[]byte(s)` … `string(b)` round-trips, or working in
  `string` for I/O that's naturally `[]byte`.
- **Why:** conversions allocate; the `bytes` package mirrors `strings` (`bytes.Contains`,
  `bytes.Index`, `bytes.Split`, …) so you can often stay in `[]byte`.
- **Fix:** keep a workflow in one representation; prefer `[]byte` for I/O; use the `bytes`
  equivalents instead of converting to string.

## #41 - Substring and memory leaks
- **Applies to:** all versions (`strings.Clone` ≥ Go 1.18).
- **Detection (judgment):** taking a small substring of a large string and keeping it long
  term.
- **Why:** a substring shares the original string's backing byte array, keeping the whole
  large string alive.
- **Fix:** copy explicitly, or use `strings.Clone(s[:n])` (≥ 1.18) / `bytes.Clone` (≥ 1.20)
  to detach the substring from the original backing array.

## #42 - Not knowing which type of receiver to use
- **Applies to:** all versions.
- **Detection (judgment):** inconsistent value/pointer receivers on the same type; value
  receiver on a type that's mutated or large; pointer receiver on a map/channel/func.
- **Why:** the wrong choice causes copies, mutation bugs, or compile errors.
- **Fix:** rules of thumb -
  - **Must be pointer:** method mutates the receiver; receiver contains a non-copyable
    field (e.g. `sync.*`).
  - **Should be pointer:** receiver is large.
  - **Must be value:** need to enforce immutability; receiver is a map/func/channel (value
    required - else compile error).
  - **Should be value:** small struct/basic type/slice that isn't mutated (e.g.
    `time.Time`).
  - When in doubt, use a pointer receiver; be consistent across the type's methods.

## #43 - Never using named result parameters
- **Applies to:** all versions.
- **Detection (judgment):** functions returning multiple values of the same type without
  names, where names would aid readability.
- **Why:** named results improve readability (especially same-typed returns) and are
  zero-initialized.
- **Fix:** name result parameters when they clarify the signature (e.g. `(lat, lng
  float32, err error)`). Use sparingly.

## #44 - Unintended side effects with named result parameters
- **Applies to:** all versions.
- **Detection (judgment):** a named result that's returned without ever being assigned
  (still its zero value) - especially `return ..., err` where `err` was never set.
- **Why:** named results are zero-initialized; returning one you forgot to assign yields
  `nil`/zero silently.
- **Fix:** make sure every named result you return has been assigned; prefer explicit
  return values when the zero value could mask a bug.
```go
func f() (err error) {
    if ctx.Err() != nil {
        return 0, 0, err // bug: err is still nil
    }
}
```

## #45 - Returning a nil receiver
- **Applies to:** all versions.
- **Detection (judgment):** a function returning an interface type that returns a typed nil
  pointer (`var t *T; return t`).
- **Why:** a typed nil pointer boxed in an interface is *not* `nil` to the caller
  (`err != nil` is true) - a classic Go gotcha.
- **Fix:** return an explicit untyped `nil`, not a nil pointer of a concrete type:
```go
func f() error {
    var p *MyErr = nil
    return p      // WRONG: caller sees non-nil error
    return nil    // correct
}
```

## #46 - Using a filename as a function input
- **Applies to:** all versions.
- **Detection (judgment):** a function taking a `string` filename and opening a file
  internally (other than `os.Open` itself).
- **Why:** couples the function to the filesystem, hurting reuse and testability.
- **Fix:** accept an `io.Reader`/`io.Writer` so callers can supply files, strings, HTTP
  bodies, etc.

## #47 - Ignoring how defer arguments and receivers are evaluated
- **Applies to:** all versions.
- **Detection (judgment):** `defer f(x)` where `x` is meant to reflect the value *at
  return time*, but is evaluated immediately at the `defer` call.
- **Why:** `defer` evaluates arguments and the receiver *now*, not at return.
- **Fix:** pass a pointer, or wrap in a closure so the variable is read at return:
```go
defer func() { notify(status) }()      // closure: reads status at return
// or
defer notify(&status)                  // pointer: address is stable
```
  (Method receivers are also evaluated immediately - same fix.)

## #48 - Panicking
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `panic(` calls.
- **Why:** `panic` stops the goroutine; it should be reserved for unrecoverable conditions
  (programmer error, mandatory dependency that can't be loaded).
- **Fix:** return an `error` for expected/expected-handlable failures. Reserve `panic` for
  truly unrecoverable conditions or `init`-time invariant violations.

## #49 - Ignoring when to wrap an error
- **Applies to:** error wrapping (`%w`) ≥ Go 1.13.
- **Detection (judgment):** `fmt.Errorf("...: %v", err)` where wrapping with `%w` would let
  callers use `errors.Is`/`As`; or wrapping where it creates unwanted coupling.
- **Why:** wrapping adds context and marks the error but exposes the source error to
  callers (coupling). Use `%w` to wrap (callers can inspect); use `%v` to *transform* (hide
  the source).
- **Fix:**
```go
fmt.Errorf("load config: %w", err)  // wrap - callers can errors.Is/As
fmt.Errorf("load config: %v", err)  // transform - source hidden
```

## #50 - Comparing an error type inaccurately
- **Applies to:** ≥ Go 1.13 (error wrapping).
- **Detection:** `scan.sh` flags error type assertions/switches (`err.(*T)`, `switch err :=
  err.(type)`, `switch err.(type)`) that should use `errors.As`.
- **Why:** if the error is wrapped, a direct type assertion fails; `errors.As` unwraps the
  chain.
- **Fix:**
```go
var p *os.PathError
if errors.As(err, &p) { ... }        // handles wrapped errors
// (Go 1.26+: if p, ok := errors.AsType[*os.PathError](err); ok { ... })
```

## #51 - Comparing an error value inaccurately
- **Applies to:** ≥ Go 1.13 (error wrapping).
- **Detection:** `scan.sh` flags `err == ErrFoo` / `err != ErrFoo` comparisons against
  sentinel errors.
- **Why:** with wrapping, a direct `==` fails; `errors.Is` unwraps the chain.
- **Fix:**
```go
if errors.Is(err, ErrFoo) { ... }    // handles wrapped errors
```

## #52 - Handling an error twice
- **Applies to:** all versions.
- **Detection (judgment):** an error that is both logged and returned (often across
  layers), so it gets logged repeatedly.
- **Why:** logging *is* handling; handling twice clutters logs and obscures the source.
- **Fix:** handle each error once - either log it or return it. Wrap to add context when
  returning.

## #53 - Not handling an error
- **Applies to:** all versions.
- **Detection (judgment):** a function call returning an `error` whose result is discarded
  (not assigned, not `_ =`).
- **Why:** silent dropped errors hide bugs; readers can't tell if it was intentional.
- **Fix:** if you intentionally ignore an error, make it explicit with the blank
  identifier and a comment: `_ = notify() // at-most-once delivery; OK to drop`.

## #54 - Not handling defer errors
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `defer` calls that discard an error result without `_ =`
  (e.g. `defer f.Close()` where `Close` returns `error`, `defer rows.Close()`, `defer
  json.NewDecoder(...).Decode(...)`).
- **Why:** a dropped defer error is indistinguishable from a forgotten one; close/decode
  errors can matter.
- **Fix:** handle it, propagate it, or make the drop explicit:
```go
defer func() { _ = f.Close() }()
// or capture for later inspection
var closeErr error
defer func() { closeErr = f.Close() }()
```

> These are conceptual mistakes; detection is by judgment (reviewing concurrency design),
> not grep.

## #55 - Mixing up concurrency and parallelism
- **Applies to:** all versions.
- **Detection (judgment):** conflating the two in design.
- **Why:** concurrency is about *structure* (decomposing into coordinating goroutines);
  parallelism is about *execution* (running in parallel). Concurrency enables parallelism.
- **Fix:** structure the problem concurrently first; parallelism falls out naturally.

## #56 - Thinking concurrency is always faster
- **Applies to:** all versions.
- **Detection (judgment):** parallelizing trivial workloads and assuming a speedup.
- **Why:** synchronization/coordination has overhead; for minimal workloads a sequential
  version can be faster.
- **Fix:** benchmark sequential vs concurrent before committing to a concurrent design.

## #57 - Being puzzled about when to use channels or mutexes
- **Applies to:** all versions.
- **Detection (judgment):** forcing channels (or mutexes) everywhere regardless of need.
- **Why:** parallel goroutines (same step, shared resource) need *synchronization* ->
  mutexes; concurrent goroutines (different steps) need *coordination/ownership transfer* ->
  channels.
- **Fix:** use mutexes to protect shared state; use channels to coordinate/transfer
  ownership. Treat them as complementary.

## #58 - Not understanding race problems (data races vs race conditions)
- **Applies to:** all versions.
- **Detection:** `scan.sh` recommends `-race`; judgment for shared-variable access without
  synchronization.
- **Why:** a *data race* is simultaneous access to one memory location with a writer
  (detected by `-race`). A *race condition* is behavior depending on timing/sequencing -
  possible even with no data race.
- **Fix:** prevent data races with `sync/atomic`, mutexes, or channels. Understand that
  data-race-free ≠ deterministic.

## #59 - Not understanding the concurrency impacts of a workload type
- **Applies to:** all versions.
- **Detection (judgment):** spawning CPU-bound workers far beyond `GOMAXPROCS`, or
  mis-sizing I/O-bound pools.
- **Why:** CPU-bound work should be bounded near the core count; I/O-bound sizing depends on
  the external system.
- **Fix:** for CPU-bound workers, keep the count near `runtime.GOMAXPROCS(0)`; for
  I/O-bound, size by the external system's capacity.

## #60 - Misunderstanding Go contexts
- **Applies to:** all versions.
- **Detection (judgment):** long-running/user-facing functions that don't accept a
  `context.Context`; ignoring `ctx.Done()`.
- **Why:** a context carries a deadline, cancellation signal, and values across API
  boundaries; functions users wait for should accept one so callers can abort.
- **Fix:** pass `context.Context` as the first arg to functions that do I/O or block; honor
  cancellation via `ctx.Done()` / `ctx.Err()`.

## #61 - Propagating an inappropriate context
- **Applies to:** all versions (`context.WithoutCancel` ≥ Go 1.21).
- **Detection (judgment):** passing a request-scoped context to a goroutine that outlives
  the request (e.g. an async publish spawned in an HTTP handler using `r.Context()`).
- **Why:** the request context is canceled when the response is written, so the async work
  can fail unexpectedly.
- **Fix:** decouple with `context.WithoutCancel(r.Context())` (≥ 1.21) or a fresh
  `context.Background()` for work that must outlive the request.

## #62 - Starting a goroutine without knowing when to stop it
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `go ` goroutine launches for a leak review (especially
  bare `go func()` with no stop signal). Judgment: a started goroutine with no shutdown
  plan.
- **Why:** goroutines are cheap to start but are resources; without a stop plan they leak.
- **Fix:** have a clear lifecycle - cancel via context, signal via channel, or `WaitGroup`/
  `errgroup`; block the parent until cleanup completes where resources are involved.

## #63 - Not being careful with goroutines and loop variables
- **Applies to:** **only Go < 1.22.** *Not a mistake from Go 1.22* (loop variables are
  per-iteration).
- **Detection (judgment, Go < 1.22 only):** a goroutine/closure launched inside a loop that
  captures the loop variable.
- **Why:** pre-1.22, all iterations share one loop variable; goroutines see the last value.
- **Fix (Go < 1.22):** shadow in the loop body: `for _, v := range items { v := v; go
  f(v) }`.

## #64 - Expecting deterministic behavior using select and channels
- **Applies to:** all versions.
- **Detection (judgment):** a `select` with multiple ready cases where code assumes the
  first-listed wins.
- **Why:** if multiple cases can proceed, `select` chooses *pseudo-randomly* (not source
  order) to prevent starvation.
- **Fix:** don't rely on case order; use a single channel or unbuffered channels to enforce
  a single producer when order matters.

## #65 - Not using notification channels
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `chan bool` used as a notification/signal channel.
- **Why:** a `chan bool` carries a meaningless value (what does `false` signal?); a
  notification carries no data.
- **Fix:** use `chan struct{}` (or `chan struct{}{}` close) for signals.

## #66 - Not using nil channels
- **Applies to:** all versions.
- **Detection (judgment):** complex `select`/merge logic that could be simplified by
  disabling a case with a nil channel.
- **Why:** sending to / receiving from a nil channel blocks forever, so assigning `nil` to
  a channel *removes* its `select` case.
- **Fix:** in a merge/fan-in, set a channel to `nil` once it's closed to drop it from the
  `select`.

## #67 - Being puzzled about channel size
- **Applies to:** all versions.
- **Detection (judgment):** buffered channels with an arbitrary/large size and no rationale.
- **Why:** only unbuffered channels give strong synchronization; a buffered channel size
  should be justified.
- **Fix:** default to unbuffered; if buffering is needed, default to size 1. Justify other
  sizes (worker-pool count, rate limiting).

## #68 - Forgetting about possible side effects with string formatting
- **Applies to:** all versions.
- **Detection (judgment):** formatting (`%v`/`%s`/`%+v`) of a value whose `String()`/
  `Format()` acquires a lock already held - deadlock risk; or formatting that reads mutable
  state → data race.
- **Why:** `%v` calls `String()`, which can deadlock if it locks a mutex the caller holds,
  or race if it reads shared state.
- **Fix:** don't format a value that needs a held lock; access fields directly, or narrow
  the lock scope before formatting.

## #69 - Creating data races with append
- **Applies to:** all versions.
- **Detection (judgment):** `append` on a shared slice from multiple goroutines,
  especially when the slice has spare capacity.
- **Why:** `append` to a non-full slice mutates the backing array in place → data race.
- **Fix:** don't share a slice for concurrent `append`; each goroutine should work on its
  own copy, or protect access with a mutex.

## #70 - Using mutexes inaccurately with slices and maps
- **Applies to:** all versions (`maps.Clone` ≥ Go 1.21).
- **Detection (judgment):** assigning a map/slice to a local var after releasing the lock
  (`m := c.balances; c.mu.RUnlock()`) and then reading it - the local shares the backing
  data.
- **Why:** maps and slices are headers over shared data; copying the header doesn't copy
  the data → data race.
- **Fix:** hold the lock for the whole operation, or deep-copy before releasing
  (`m := maps.Clone(c.balances)` ≥ 1.21, or `slices.Clone`).

## #71 - Misusing sync.WaitGroup
- **Applies to:** all versions (`wg.Go` ≥ Go 1.25 simplifies this).
- **Detection:** `scan.sh` flags `wg.Add(` for placement review (verify it is *not* called
  inside the goroutine it counts).
- **Why:** `Add` must happen before `Wait` could return; calling `Add` *inside* the
  goroutine races with `Wait` → non-deterministic counts and data races.
- **Fix:** call `wg.Add` before launching (before the loop, or in the loop body but outside
  the goroutine). On ≥ 1.25, prefer `wg.Go(func(){...})`.

## #72 - Forgetting about sync.Cond
- **Applies to:** all versions.
- **Detection (judgment):** hand-rolled "wait for a condition, notify many" loops using
  channels where `sync.Cond` fits.
- **Why:** `sync.Cond` broadcasts repeated notifications to multiple waiters - awkward to
  do with channels.
- **Fix:** reach for `sync.Cond` when you need to broadcast a condition to multiple
  goroutines repeatedly.

## #73 - Not using errgroup
- **Applies to:** all versions (`golang.org/x/sync/errgroup`).
- **Detection (judgment):** `sync.WaitGroup`-driven fan-out that needs to fail-fast on the
  first error and/or carry a context.
- **Why:** `errgroup` synchronizes a group of goroutines, propagates the first error, and
  can cancel the group on error.
- **Fix:**
```go
g, ctx := errgroup.WithContext(ctx)
for _, item := range items {
    item := item
    g.Go(func() error { return process(ctx, item) }) // ≥1.25 WaitGroup.Go style
}
if err := g.Wait(); err != nil { ... }
```

## #74 - Copying a sync type
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `sync.WaitGroup`/`sync.Mutex`/`sync.RWMutex`/`sync.Once`/
  `sync.Cond`/`sync.Map`/`atomic.*` passed by value (function params/returns or embedded by
  value then copied); judgment for value receivers on types containing them.
- **Why:** copying a `sync` type duplicates its internal state → races and broken
  synchronization. `go vet`'s `copylocks` analyzer catches this.
- **Fix:** pass `sync` types by pointer; never give a type with a `sync` field a value
  receiver; embed by pointer.

## #75 - Providing a wrong time duration
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `time.NewTicker(`, `time.After(`, `time.Sleep(`,
  `time.NewTimer(`, `time.Tick(` called with a bare integer/float literal (e.g.
  `time.NewTicker(1000)`).
- **Why:** `time.Duration` is in *nanoseconds*; `1000` means 1µs, not 1 second.
- **Fix:** use the `time` API: `time.Second`, `100 * time.Millisecond`, etc.
```go
time.NewTicker(time.Second)
time.Sleep(250 * time.Millisecond)
```

## #76 - `time.After` and memory leaks
- **Applies to:** **only Go < 1.23.** *Not a mistake from Go 1.23* (the GC reclaims
  unreferenced tickers/timers; `Stop` is no longer needed to help the GC).
- **Detection (Go < 1.23 only):** `scan.sh` flags `time.After` inside a `select` within a
  loop.
- **Why:** pre-1.23, each `time.After` allocates a timer not GC'd until it fires, so a loop
  using `time.After` leaks timers.
- **Fix (Go < 1.23):** use `time.NewTimer` + `defer t.Stop()` (reset per iteration) instead
  of `time.After` in hot loops.

## #77 - JSON handling common mistakes
- **Applies to:** all versions.
- **Sub-issues & detection:**
  - **Embedded `time.Time`** (judgment): an embedded `time.Time` implements
    `json.Marshaler`, overriding the default marshaling of the whole struct. Don't embed
    `time.Time`; use a named field.
  - **Monotonic clock** (judgment): comparing two `time.Time` with `==` compares both wall
    and monotonic clocks; two "equal" times can differ. Use `t1.Equal(t2)`.
  - **Map of `any` / `interface{}`** (judgment): JSON numbers unmarshal to `float64` by
    default - large ints lose precision. Unmarshal into a typed struct or
    `json.Number` (`dec.UseNumber()`).
- **Fix:** name (don't embed) `time.Time`; use `.Equal`; use typed structs / `json.Number`.

## #78 - Common SQL mistakes
- **Applies to:** all versions.
- **Sub-issues & detection (judgment):**
  - **`sql.Open` doesn't connect:** call `db.Ping()`/`PingContext()` to verify reachability.
  - **Connection pooling:** configure `db.SetMaxOpenConns`, `SetMaxIdleConns`,
    `SetConnMaxLifetime` for production.
  - **Prepared statements:** use `db.Prepare`/`QueryRowContext` with placeholders for
    efficiency and SQL-injection safety - never `fmt.Sprintf` SQL values.
  - **Null values:** use `*T` pointers or `sql.Null[T]` (≥1.22)/`sql.NullString` for
    nullable columns.
  - **Rows iteration errors:** call `rows.Err()` after the `for rows.Next()` loop.
- **Fix:** apply each of the above; always `defer rows.Close()`.

## #79 - Not closing transient resources (HTTP body, sql.Rows, os.File)
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `http.Get`/`http.Post`/`client.Do`/`http.NewRequest`+
  `client.Do` and `os.Open`/`os.Create` without a matching `defer ...Close()`;
  `sql.Query` without `defer rows.Close()`.
- **Why:** every `io.Closer` must eventually be closed or you leak file descriptors /
  connections.
- **Fix:** `defer resp.Body.Close()` (handle its error), `defer rows.Close()`, `defer
  f.Close()`.

## #80 - Forgetting the return statement after replying to an HTTP request
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `http.Error(` not followed (within the same block) by a
  `return`.
- **Why:** `http.Error` does *not* stop the handler; execution continues and writes a
  success body/status after the error.
- **Fix:** add `return` after `http.Error`:
```go
if err != nil {
    http.Error(w, "foo", http.StatusInternalServerError)
    return
}
```

## #81 - Using the default HTTP client and server
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `http.Get`/`http.Post`/`http.Head`/`http.DefaultClient`/
  `http.DefaultTransport` and `http.ListenAndServe`/`http.Server{}` without timeouts.
- **Why:** the default client/server have **no timeouts** - fine for examples, dangerous in
  production (slowloris, hung connections).
- **Fix:** configure a custom `http.Client` with a `Timeout` (and `Transport`), and a
  custom `http.Server` with `ReadTimeout`/`WriteTimeout`/`IdleTimeout`.
```go
client := &http.Client{Timeout: 10 * time.Second}
srv := &http.Server{
    Addr: ":8080", ReadTimeout: 5*time.Second, WriteTimeout: 10*time.Second, IdleTimeout: 120*time.Second,
}
```

## #82 - Not categorizing tests (build tags, env vars, short mode)
- **Applies to:** all versions.
- **Detection (judgment):** integration/long tests mixed with unit tests with no way to
  separate them.
- **Why:** running slow/integration tests on every save is wasteful.
- **Fix:** separate with build tags (`//go:build integration`), env vars, or
  `testing.Short()` + `-short`; run the right subset in CI.

## #83 - Not enabling the race flag
- **Applies to:** all versions.
- **Detection:** `scan.sh` checks for `-race` in CI config / Makefile / scripts, and
  recommends it for concurrent code.
- **Why:** `-race` instruments memory accesses at runtime to catch data races the compiler
  can't.
- **Fix:** run `go test -race ./...` in local testing and CI. Exclude specific files with
  `//go:build !race` if needed.

## #84 - Not using test execution modes (parallel and shuffle)
- **Applies to:** all versions.
- **Detection (judgment):** long tests not marked `t.Parallel()`; no `-shuffle` use.
- **Why:** `-parallel` speeds up long tests; `-shuffle=on` exposes order-dependence.
- **Fix:** call `t.Parallel()` in independent tests; run CI with `-shuffle=on` sometimes.

## #85 - Not using table-driven tests
- **Applies to:** all versions.
- **Detection (judgment):** many near-identical test functions testing one function with
  different inputs.
- **Why:** table-driven tests deduplicate and make adding cases trivial.
- **Fix:**
```go
tests := []struct{ name string; in int; want int }{ /* ... */ }
for _, tt := range tests {
    tt := tt
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        if got := f(tt.in); got != tt.want { t.Errorf("got %d want %d", got, tt.want) }
    })
}
```

## #86 - Sleeping in unit tests
- **Applies to:** all versions.
- **Detection:** `scan.sh` flags `time.Sleep` in `*_test.go`.
- **Why:** sleeps make tests slow and flaky; they paper over timing assumptions.
- **Fix:** synchronize on a signal (channel, `WaitGroup`, `sync.Cond`) or a condition; if
  unavoidable, use a retry/`eventually` helper instead of a fixed sleep.

## #87 - Not dealing with the time API efficiently
- **Applies to:** all versions.
- **Detection (judgment):** tests depending on wall-clock time / real `time.Now()`.
- **Why:** real time makes tests flaky and slow.
- **Fix:** inject a clock (pass `time.Time` or a `Clock` interface), or use a fake; on ≥1.24
  prefer `t.Context()` and time-abstraction helpers.

## #88 - Not using testing utility packages (httptest and iotest)
- **Applies to:** all versions.
- **Detection (judgment):** tests standing up real HTTP servers or real files where
  `httptest`/`iotest` would do.
- **Why:** `httptest.NewServer`/`NewRecorder` test HTTP clients/servers without a network;
  `iotest` tests error tolerance of `io.Reader` consumers.
- **Fix:** use `httptest` for HTTP, `iotest` for reader robustness.

## #89 - Writing inaccurate benchmarks
- **Applies to:** all versions (`b.Loop()` ≥ Go 1.24).
- **Detection:** `scan.sh` flags `for i := 0; i < b.N; i++` benchmark loops (use `b.Loop()`
  on ≥ 1.24); judgment for compiler-defeating benchmarks.
- **Why:** the compiler can eliminate work with no observable side effect, fooling you;
  `b.N` loops also reset/pollute `b.StartTimer`/`StopTimer`. `b.Loop()` (≥1.24) is simpler
  and more correct.
- **Fix:** ensure a side effect (assign to a package-level `var` / `b.SetBytes`); use
  `b.Loop()` on ≥ 1.24; compare with `benchstat`; reset timers with `b.ResetTimer()`.

## #90 - Not exploring all the Go testing features
- **Applies to:** all versions.
- **Sub-issues & detection (judgment):**
  - **Coverage:** run `go test -coverprofile` and review gaps.
  - **Testing from a different package:** put unit tests in `package foo_test` (external) to
    test only the exported API.
  - **Utility funcs:** use `t.Fatal`/`t.Helper` instead of `if err != nil { log.Fatal }`.
  - **Setup/teardown:** use `t.Cleanup` for setup/teardown ordering.
  - **Fuzzing** (community mistake): add `func FuzzX(f *testing.F)` targets; run
    `go test -fuzz=FuzzX` to find malformed-input crashes.

> These are performance-design mistakes, mostly requiring judgment / profiling rather than
> grep. They matter for CPU- or allocation-sensitive code; don't prematurely optimize.

## #91 - Not understanding CPU caches
- **Applies to:** all versions.
- **Detection (judgment):** data-intensive code ignoring cache behavior (random memory
  access, pointer chasing) where contiguous access would help.
- **Why:** L1 cache is ~50–100× faster than main memory; the CPU fetches 64-byte cache
  lines. Spatial locality and cache-line alignment matter for CPU-bound code.
- **Fix:** prefer contiguous data (slice of structs vs. struct of slices depending on
  access pattern), unit/constant strides, and cache-friendly layouts.

## #92 - Writing concurrent code that leads to false sharing
- **Applies to:** all versions.
- **Detection (judgment):** multiple goroutines writing to adjacent fields of a shared
  struct on different cores (each invalidates the other's cache line).
- **Why:** lower-level caches aren't shared across cores; writes to vars on the same cache
  line thrash the line ("false sharing") even though the goroutines touch *different*
  fields.
- **Fix:** pad fields so concurrent writers land on different cache lines, or have each
  goroutine work on separate memory.

## #93 - Not taking into account instruction-level parallelism
- **Applies to:** all versions.
- **Detection (judgment):** CPU-bound loops with data hazards that serialize instructions.
- **Why:** the CPU executes independent instructions in parallel (ILP); data dependencies
  limit it.
- **Fix:** identify and reduce data hazards; allow the CPU to issue more parallel
  instructions (e.g. independent accumulators in a reduction).

## #94 - Not being aware of data alignment
- **Applies to:** all versions.
- **Detection (judgment):** structs with fields ordered so padding wastes space (e.g. a
  `bool` between two `int64`s). `maligned`/`fieldalignment` (`go vet -fieldalignment`)
  reports it.
- **Why:** basic types are aligned to their size; poor ordering adds padding -> larger
  structs and worse cache locality.
- **Fix:** order struct fields by size, descending, to minimize padding and tighten the
  layout.

## #95 - Not understanding stack vs. heap
- **Applies to:** all versions.
- **Detection (judgment):** unnecessary heap allocations (escaping pointers) where a stack
  value would do; `go build -gcflags=-m` shows escapes.
- **Why:** stack allocations are nearly free; heap allocations need GC.
- **Fix:** avoid returning pointers to locals that don't need to escape; prefer value
  returns; check escapes with `-gcflags=-m`.

## #96 - Not knowing how to reduce allocations
- **Applies to:** all versions.
- **Detection (judgment):** hot paths allocating per call (e.g. returning `[]byte` that's
  immediately discarded, `fmt.Sprintf` in a loop).
- **Why:** allocations dominate many workloads.
- **Fix:** design APIs to avoid "sharing up" (return values, accept a destination buffer
  like `io.Writer`/`Append*`), rely on compiler optimizations (e.g. `strings.Builder`,
  escape elimination), and use `sync.Pool` for reusable buffers.

## #97 - Not relying on inlining
- **Applies to:** all versions.
- **Detection (judgment):** small hot functions that the inliner refuses (`//go:noinline`
  or too complex), or wrapping that defeats inlining.
- **Why:** inlining removes call overhead and enables further optimizations.
- **Fix:** keep hot functions small and inlineable; use the "fast-path inlining" technique
  (small inlineable wrapper + an out-of-line slow path) to reduce amortized call cost.

## #98 - Not using Go diagnostics tooling
- **Applies to:** all versions.
- **Detection (judgment):** optimizing blind without profiling.
- **Why:** you must measure before optimizing - intuition is unreliable.
- **Fix:** use `pprof` (CPU, memory, block, mutex profiles) and the execution tracer
  (`go tool trace`); `go test -bench` + `benchstat` for comparisons.

## #99 - Not understanding how the GC works
- **Applies to:** all versions.
- **Detection (judgment):** tuning allocation pressure / heap size without understanding the
  GC, or fighting the GC with `runtime.GC()` calls.
- **Why:** understanding GC tuning (e.g. `GOGC` / `GOMEMLIMIT`) helps handle load spikes and
  memory bounds.
- **Fix:** tune `GOGC`/`GOMEMLIMIT` based on profiling; reduce allocation rate to lower GC
  frequency; don't call `runtime.GC()` as a workaround.

## #100 - Not understanding the impacts of running Go in Docker and Kubernetes
- **Applies to:** **only Go < 1.25.** *Not a mistake from Go 1.25* (Go automatically sets
  `GOMAXPROCS` to the cgroup CPU quota in containers).
- **Detection (Go < 1.25 only):** `scan.sh` checks `Dockerfile`/`*.yaml` for container CPU
  limits without an explicit `GOMAXPROCS`/`automaxprocs` workaround.
- **Why:** pre-1.25, `GOMAXPROCS` defaulted to the host CPU count, ignoring the cgroup
  quota - causing oversubscription and throttling (the "noisy neighbor" / CFS throttle
  problem) in containers.
- **Fix (Go < 1.25):** set `GOMAXPROCS` explicitly, or use `go.uber.org/automaxprocs`.
  From Go 1.25 no action is needed.

