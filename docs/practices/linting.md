# Linting (SwiftLint, report-only)

`.swiftlint.yml` turns on SwiftLint for the bug classes that are cheap to catch early and
turns off everything that clashes with the house style (long lines, long files, short
math names, formatting rules); every disabled rule carries a one-line reason in the file.
Enforced: `force_cast`, `force_try`, `force_unwrapping`, `identical_operands`,
`unowned_variable_capture`, `weak_delegate`, `duplicate_imports`, `unused_*`,
`empty_count`, `first_where`, `yoda_condition`, `unneeded_override` and the other correctness
rules listed there. Excluded: `.build`, `Sources/MetalUIIconData` (vendored Lucide) and `docs/probes`.

Existing violations are frozen in `.swiftlint-baseline.json`, so the check prints only
**new** ones:

```bash
swiftlint lint --baseline .swiftlint-baseline.json     # must print nothing on master
```

The `Lint` workflow runs the same command (SwiftLint 0.65.1, the `ghcr.io/realm/swiftlint`
container) on every pull request and master push and shows new violations as annotations.
It is report-only (`continue-on-error: true`); remove that line to make it blocking.

After fixing violations, refresh the baseline so it shrinks:

```bash
swiftlint lint --write-baseline .swiftlint-baseline.json
```

The baseline should only shrink: never regenerate it to absorb a new violation. Fix the
code instead (or, for a deliberate exception, say why in the PR). Baseline entries match on
rule, file and source text, not line number, so unrelated edits do not disturb them.
