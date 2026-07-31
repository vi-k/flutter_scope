### Task 18: релиз 0.10.0

**Files:**
- Modify: `pubspec.yaml:4`, `CHANGELOG.md`

- [ ] **Step 1:** `version: 0.10.0`; секция CHANGELOG:

```markdown
## 0.10.0

* [breaking changes] Unify dependency path format: no leading `/` in
  `ScopeDependencyException.name`, `ScopeDependencyInfo.path` and progress
  paths; anonymous groups add no separator.
* [breaking changes] Remove dead API: `LiteScopeInitState`/`Waiting`/
  `Progress`/`Ready`, `typeToShortString`; rename
  `ScopeDependencyNoDisposalRequred` to `ScopeDependencyNoDisposalRequired`.
* Fix infinite recursion in `CompareUtils.identical`.
* Fix hang in `ScopeAutoDependencies.dispose()` when no dependency requires
  disposal.
* Fix `ScopeNotifier.value` not subscribing to a new listenable on update.
* Fix `LiteScope.close()` hang outside the Ready state; fix
  `ScreenshotReplacer` completing early and leaking `ui.Image`.
* Guard AsyncScope post-frame callbacks with `mounted`.
* Log dependency disposal errors instead of swallowing them.
* Fix unbalanced parenthesis in `AsyncScopeError.toString()`.
* Add `repository`, `issue_tracker` and `topics` to pubspec; honest Flutter
  constraint.
* Rewrite README; sync the pub.dev example; real `debug`/`Scope` doc pages.
```

- [ ] **Step 2: полная верификация** — `flutter analyze` (корень + оба example) → 0; `flutter test` → все зелёные; `flutter pub publish --dry-run` → 0 warnings; запустить `example/scopo_demo` (`flutter run -d macos`) и прокликать вкладки Scope/LiteScope/AsyncScope — прогресс-пути в консоли без ведущего `/`, закрытие вкладок не виснет.
- [ ] **Step 3:** коммит `release 0.10.0`, тег `v0.10.0`, `git push origin main v0.10.0`, `flutter pub publish --force`.

---

## Verification (сквозная)

1. `flutter test` — **0 failed** (было 17/17 failed); в сьюте появились: тест анонимных групп, 19 тестов `Notifier`, регрессионные тесты Задач 4–9.
2. `flutter analyze` в корне, `example/minimal`, `example/scopo_demo` — 0 issues (было 3).
3. `flutter pub publish --dry-run` — 0 warnings.
4. Ручной прогон `scopo_demo` на macOS: все 9 вкладок открываются/закрываются, консольные пути единообразны.
5. После публикации: страница pub.dev показывает Repository-ссылку, топики, changelog на страницах 0.9.4/0.9.5, компилируемый Example-таб.
