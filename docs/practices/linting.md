# Linting (SwiftLint)

The rule is **do not turn lint off**: fix the code, or tune the rule's options, before
disabling anything. A disable (in `.swiftlint.yml` or inline) is the last resort and carries
its reason beside it. Never rename an identifier just to dodge a rule, and never write
`count < 1` to dodge `empty_count`.

`.swiftlint.yml` runs SwiftLint's whole default rule set plus the opt-in rules listed there.
Four things are tuned rather than disabled:

- **Metric rules** (`line_length`, `file_length`, `type_body_length`, `function_body_length`,
  `cyclomatic_complexity`, `function_parameter_count`, `large_tuple`, `nesting`) have thresholds
  near the tail of today's tree, so they catch outliers, not the norm.
- **Names** (`identifier_name`, `type_name`) allow one-letter and `_x` names; sentence-style
  test names already fit the default 40/60 maximum.
- **Test code** has its own `Tests/.swiftlint.yml` and `Backends/SDL/Tests/.swiftlint.yml`
  (a nested config merges over the root): longer pinned-data lines, and `empty_string` and
  `empty_collection_literal` off, because `#expect(x == "")` and `#expect(x == [])` state the
  expected value and `.isEmpty` does not compile for an optional. Both rules stay on for sources.
- **`switch_case_alignment`** ignores a whole `switch` written on one line.

Metric outliers are not in the baseline: a metric message carries its count (`currently contains 5221`), so any
edit would unmatch the entry. Each carries an inline disable with a reason instead (below).
Existing violations are frozen in `.swiftlint-baseline.json`, so the check prints only
**new** ones:

```bash
swiftlint lint --strict --baseline .swiftlint-baseline.json     # must print nothing and exit 0 on master
```

The `Lint` workflow runs the same command (SwiftLint 0.65.1, the `ghcr.io/realm/swiftlint`
container) on every pull request and master push, shows new violations as annotations and
fails the check on any. `--strict` is what makes warnings fail; without it only errors do.

After fixing baselined violations, refresh the baseline so it shrinks:

```bash
swiftlint lint --write-baseline .swiftlint-baseline.json
```

The baseline should only shrink: never regenerate it to absorb a new violation. Fix the
code instead (or, for a deliberate exception, say why in the PR). Baseline entries match on
rule, file and source text, not line number, so unrelated edits do not disturb them.

SwiftLint's autocorrect (`swiftlint --fix`) has deleted `@testable import` lines, turned a
deliberate `>= 0` into `.isEmpty`, removed the `?? nil` that flattens a `T??`, and deleted an
explicit init whose doc comment recorded why it is internal. Review every hunk of an autocorrect.

## What each formerly disabled rule measured, and what was decided (2026-11-24)

"Hits" is the count over `Sources`, `Tests`, `Backends/SDL` and `Examples` with the rule on
and its default options. "Left" is what remains: **0** when the tree is clean, otherwise the number of baselined
entries (formatting rules, in the hot directories `Sources/MetalUI` and `Sources/MetalUITextSystem`)
or, for metric rules, of inline-suppressed outliers (listed below).

| Rule | Hits | Decision | Left | Reason / settings |
|---|---:|---|---:|---|
| `line_length` | 10198 | on, 250 / 400, comments and URLs ignored; tests 600 / 1000 | 2 | Code lines: Sources p50 52, p99 122, p99.9 149, max 580. Test data (pinned paths, glyph runs, grid corpora) is long by design: p99 132, max 715. Four test lines and one SDL line were wrapped; the two left are `@available` messages in `Box.swift`. |
| `file_length` | 308 | on, 2000 / 6000 | 5 | p50 170, p99 1395, max 5214 lines. Left: `Frame`, `Window`, `LayoutTree`, `NativeGridTests`, `AnimationTests`. |
| `type_body_length` | 48 | on, 1000 / 2500 | 4 | p50 8, p99 275, max 2142. Left: `Frame`, `Window`, `LayoutTree`, `CodeDecorations`. |
| `function_body_length` | 266 | on, 200 / 500 | 8 | p50 7, p99 58, max 443. Left: two `CodeViewPlan` functions, `Window.init`, `TableBody`, `runDemo` and three long test matrices. |
| `cyclomatic_complexity` | 237 | on, 40 / 80 | 9 | p50 3, p99 25, max 62 (switch-heavy event and layout code). |
| `function_parameter_count` | 175 | on, 12 / 20 | 2 | p50 2, p99 7, max 18 (the `TerminalView` equality helper, the SDL replay `draw`). |
| `large_tuple` | 526 | on, 7 / 12 | 1 | Geometry and fixture tuples of 3 to 7 members are the norm; the one left has 8 (`RichTextPaint`). |
| `nesting` | 33 | on, `type_level` 3 | 0 | The deepest type nesting is 3. |
| `identifier_name` | 14582 | on: `min_length 1`, `allowed_symbols ["_"]`, `excluded` single capitals | 0 | One-letter math names and `_x` helpers are the style. The default 40/60 maximum already fits every sentence-style test name. `excluded` is `A B C E H K L N W` (Lab/colour channels, width/height, fixtures). Two inline disables carry a reason: the capitalised `InvalidationRow`, which reads as a view, and the `Axis` label parameter of `validateFrameAxis`. |
| `type_name` | 27 | on: `min_length 1`, `allowed_symbols ["_"]` | 0 | `ID`, `Up`, `_ToolbarContext` and the other underscored result-builder carriers. |
| `colon` | 24 | on: `apply_to_dictionaries false`, `flexible_right_spacing true` | 0 | Aligned `key:   value` columns are the style. |
| `comma` | 77 | on | 3 | Fixed outside the hot directories; the three left are aligned columns in `Stack.swift`. |
| `trailing_comma` | 448 | on, `mandatory_comma false` (no trailing comma) | 15 | The tree is mixed and no option allows both; none is the majority style. |
| `vertical_parameter_alignment` | 65 | on | 35 | Continuation lines realigned under the first parameter outside the hot directories. |
| `vertical_whitespace` | 41 | on | 9 | Two blank lines in a row; the nine left are in hot files. |
| `trailing_newline`, `trailing_whitespace`, `leading_whitespace`, `redundant_void_return`, `syntactic_sugar` | 7, 3, 1, 1, 1 | on | 0 | Fixed. |
| `opening_brace` | 2 | on | 1 | One left in `Keymap.swift`. |
| `control_statement` | 2 | on | 1 | One left in `GradientRaster.swift`. |
| `empty_parentheses_with_trailing_closure` | 31 | on | 1 | Thirty fixed in tests; one left in `TabStrip.swift`. |
| `switch_case_alignment` | 45 | on, `ignore_one_liners true` | 0 | A whole `switch` on one line is a table, not a misaligned switch. Seventeen `case a: x; case b: y` lines were split. |
| `statement_position` | 90 | **off** | n/a | Compact `if { }` then `else if { }` chains put `else` on the next line under `if`. The 90 sites are that deliberate style; no option accepts both it and the cuddled style (the other mode flags 1466 sites), and autocorrect joins them into 200-column lines. |
| `implicit_optional_initialization` | 63 | on, `always` (omit `= nil`) | 35 | Omitting `= nil` is the majority style (the `never` style flags 1761 sites). |
| `unneeded_synthesized_initializer` | 40 | on | 37 | Two removed outside the hot directories; one kept under an inline disable because its doc comment records why it is internal (`AtlasSlot`). |
| `legacy_multiple` | 81 | on (opt-in) | 9 | `x % n == 0` became `x.isMultiple(of: n)` everywhere outside the hot directories. |
| `for_where` | 7 | on | 3 | Four fixed. The three left (`LazyUnits`, `LazyTree`) call a function that mutates `inout` state or returns, which a `where` clause cannot do. |
| `void_function_in_ternary` | 10 | on | 0 | Three real sites in `TerminalEmulator+Controls` became `if`/`else`. Seven are `cond ? AnyElement(...) : AnyElement(...)` expressions (the subject of the test), so those two test files disable the rule with a reason. |
| `inclusive_language` | 13 | on, `override_allowed_terms ["master"]` | 0 | `master` is this repository's default branch (there is no `main`) and the pty master end; every other term is still checked. |
| `todo` | 0 | on | 0 | |
| `empty_string` | 60 | on (opt-in); off in tests | 0 | All sixty are `#expect(x == "")` in tests. |
| `empty_collection_literal` | 166 | on (opt-in); off in tests | 0 | 165 are `#expect(x == [])` in tests. |
| `redundant_nil_coalescing` | 29 | **off** | n/a | Every site flattens a `T??` (`last ?? nil`, `map { optional } ?? nil`); the rule cannot see types and its autocorrect changes the type. |
| `multiple_closures_with_trailing_closure` | 194 | **off** | n/a | These are SwiftUI's own call shapes: `Button(action: { }) { label }`, `onGeometryChange(for:of:) { }`. |
| `discouraged_optional_collection` | 161 | **off** (opt-in) | n/a | `[T]?` is API: nil (not asked, unknown) differs from `[]` (asked, none). |
| `discouraged_optional_boolean` | 57 | **off** (opt-in) | n/a | `Bool?` is a deliberate tri-state (unset, yes, no), as in SwiftUI. |
| `optional_data_string_conversion` | 193 | **off** | n/a | Most sites decode `[UInt8]` or `ArraySlice<UInt8>` (terminal, Markdown, code buffer, subprocess output), which `String(data:encoding:)` cannot take. The rest decode pipe, process and clipboard `Data`, where the replacement-character result is the intent. |

## Split candidates (inline-suppressed metric outliers)

Each has `// swiftlint:disable[:next|:this] <rule> - <reason>` at its declaration, and is not split now
because that is refactoring that collides with in-flight perf branches. Split when next touched, and
delete the suppression.

- `file_length`: `Frame.swift`, `Window.swift`, `LayoutTree.swift`, `NativeGridTests.swift`, `AnimationTests.swift`.
- `type_body_length`: `Frame`, `Window`, `LayoutTree`, `CodeDecorations`.
- `function_body_length` and `cyclomatic_complexity`: `CodeViewPlan` `makePlan` and `paintContent`, `Window.init`;
  `TableBody`, `main.swift` `runDemo`, `GridElementTests`, `ModifierTests`, `OuterModifierMatrixTests` (length);
  `LegacyLowering`, `TextEditing`, `LayoutTree` (2478), `TerminalEmulator+Controls` (two), `TerminalViewModel` (complexity).
- `function_parameter_count`: `TerminalView.same`, `SDLReplayer.draw`. `large_tuple`: `RichTextPaint.pending`.
  `line_length`: two `@available` messages in `Box.swift`.

## Deferred: the hot-directory reformat

`Sources/MetalUI` and `Sources/MetalUITextSystem` carry open perf branches, so a tree-wide
autocorrect there would conflict with all of them. Their hits sit in the baseline instead.
When those branches have merged, run the plan below on the two directories, review every hunk,
build, and regenerate the baseline.

| Rule | Entries | How |
|---|---:|---|
| `unneeded_synthesized_initializer` | 37 | `swiftlint --fix` (check each removed init for a doc comment that explains it) |
| `implicit_optional_initialization` | 35 | `swiftlint --fix` |
| `vertical_parameter_alignment` | 35 | no autocorrect; realign each continuation line under the first parameter |
| `trailing_comma` | 15 | `swiftlint --fix` |
| `vertical_whitespace` | 9 | `swiftlint --fix` |
| `legacy_multiple` | 9 | rewrite `a % n == 0` to `a.isMultiple(of: n)` |
| `comma` | 3 | the aligned columns in `Stack.swift`: realign with single spaces |
| `control_statement`, `opening_brace`, `empty_parentheses_with_trailing_closure` | 1 each | `swiftlint --fix` |
| `for_where` | 3 | false positives (`inout`, early return); inline disable with a reason |

Use a throwaway config with `only_rules:` for the correctable rules above and `included:` set to
the two directories, and run `swiftlint --fix --config <file>`.
