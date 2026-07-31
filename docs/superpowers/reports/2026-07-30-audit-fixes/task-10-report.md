# Task 10 Report: Documentation of Known Async Lifecycle Issues

## Summary

Successfully documented all known async lifecycle issues in TODO.md by appending:
1. Five main issues from the brief (AsyncScopeCoordinator queuing, AsyncScopeElementBase dispose window, ScopeAutoDependencies lifecycle, test coverage gaps, test infrastructure issues)
2. Five additional issues discovered during Tasks 5-8 implementation (ScreenshotReplacer LateInitializationError, AsyncScope init-stream StateError, test infrastructure Stream.error behavior, ScopeDependencyGroup.init() empty-set guard, LiteScope render condition)

## Changes

- **File modified:** TODO.md
- **Lines added:** 12
- **Structure preserved:** Added new "Известные проблемы (0.10.x)" section after existing "Тесты:" section
- **Style maintained:** Bullet-point format consistent with file's existing style

## Commit

- **Hash:** 44b9bd5
- **Message:** "record known async lifecycle issues in TODO"
- **Files:** TODO.md only

## Verification

- `git diff --stat` shows only TODO.md modified (+12 insertions, 0 deletions)
- No other files committed
- All items preserved in correct order

## Notes

All documented issues are categorized as requiring design work or deeper architecture fixes beyond the scope of this release. They serve as reference documentation for future maintenance and design decisions.
