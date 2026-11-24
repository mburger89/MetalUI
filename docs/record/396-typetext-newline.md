# 396: `TestWindow.typeText` types a newline as Return (Sift gap G16, `HT-AD`)

Class `M` (test harness only, no divergence, no public declaration). Branch `fix/typetext-newline`, base master `595c474a`.
Requested by Sift: a focused `CodeView` holding `""` and `window.typeText("select 1;\nselect 2;")` left `select 1;select 2;`.

## Cause

`deliverKey` sends committed text only for characters `producesText` accepts, which excludes control characters, so `"\n"` went
down the key path as a key event whose characters were `"\n"`. Nothing handles that: AppKit never sends Return as `"\n"`; it sends
`"\r"` (`insertNewline:`), and `CodeView`, `TextEditor` and `TextField.onSubmit` all look for `ControlKeys.returnKey`.

## Fix

`typeText` delivers a `"\n"`, `"\r"` or `"\r\n"` Character as `typeKey(.return)` does and `"\t"` as `typeKey(.tab)`, in both the
caret and no-caret cases (`deliverKey(_:modifiers:asKeyEvent:)`); one frame at the end; the doc comment says so. Ruling `HT-AD`.

## Tests and mutations

`HarnessInputTests`: `typeTextTypesANewlineAsReturnInACodeView`, `aCarriageReturnLineFeedIsOneNewline`,
`typeTextTypesATabAsTheTabKey`, `aNewlineSubmitsASingleLineField` (4). Each mutated (the newline branch removed; the tab sent as `.textInput("\t")`, since a tab was already a key event and removing its branch changes nothing) and seen red, then restored. No steady-frame cost test: a harness-only change with no shared view code.
