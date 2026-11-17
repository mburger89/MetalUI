# 376 - The snippet model and parser (`CV-BP`)

Branch `feat/code-snippet-model` from master `9dc1e9a8`. Class M, no divergence (labels untouched). First of three snippet PRs (Alloy code-intel #1): the model and parser in `MetalUICodeBuffer`; the session (`CV-BQ`) and the keys and paint (`CV-BR`) follow.

**API.** `CodeSnippet(text:tabStops:)` (precondition: ranges in the UTF-8 bytes on scalar boundaries, non-negative indexes, nested or disjoint), `CodeSnippet(parsing:)`, `CodeSnippet.TabStop(index:range:)`. A non-trapping `isValid(text:tabStops:)` is the precondition's body so tests reach every branch.

**Parser.** Recursive descent over the UTF-8 bytes into a tree, then a render that resolves mirrors. Rules are in `CV-BP`: `$n`/`${n}`/`${n:default}` nested, escapes, first-option choices, variables as plain text (default or nothing, Alloy's answer 4; VS Code makes a placeholder of the name), transforms dropped, malformed text literal, implicit `$0`, the first non-empty default of an index is every mirror's text (text only). `$` attempts are memoised by position: without it a failed `${1:` retries its inner attempts and unclosed nesting is exponential.

**Tests** (`CodeSnippetTests`): a 39-row parser table, a linear-time pin for 2000 unclosed openers, a seeded fuzz that the parse never traps and always yields a valid snippet with a `$0`, the validity cases, Hashable. Mutations are recorded in the file's header.
