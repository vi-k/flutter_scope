### Task 8: LiteScope.close() виснет вне состояния Ready + ScreenshotReplacer

- `lib/src/scope/g_lite_scope/lite_scope_core.dart:216-244`: `close()` ждёт `_screenshotCompleter`, который комплитится только из `ScreenshotReplacer` внутри `buildOnReady()`. Если scope в `Waiting`/`Progress`/`Error` — `close()` виснет навсегда.
- `lib/src/utils/screenshot_replacer.dart:51-71`: `finally { widget.onCompleted(); }` срабатывает и на retry-путях (`boundary == null`, `debugNeedsPaint`) — барьер скриншота не работает; `_image` никогда не `dispose()`-ится — утечка `ui.Image` на каждое закрытие.

**Files:**
- Modify: `lib/src/scope/g_lite_scope/lite_scope_core.dart:216-244`
- Modify: `lib/src/utils/screenshot_replacer.dart`
- Test: Create `test/lite_scope_test.dart`

- [ ] **Step 1: падающий тест** — `LiteScope` в состоянии `Waiting` (инициализация не стартовала/не завершена), вызвать `close()`, прокрутить кадры, ожидать завершения future от `close()` (сейчас — timeout).
- [ ] **Step 2: фикс `close()`** — ждать `_screenshotCompleter` только если он реально будет закомплекчен: создавать/ждать его только когда текущее состояние — Ready (т.е. `buildOnReady` активен); иначе пропускать барьер.
- [ ] **Step 3: фикс `ScreenshotReplacer._capture()`** — убрать `onCompleted()` из `finally`; вызывать его явно в конце успешной ветки и в терминальных ошибочных ветках, но **не** на retry-путях (`return` до вызова). В `State.dispose()` добавить `_image?.dispose();`.
- [ ] **Step 4:** PASS + весь сьют. Коммит: `fix LiteScope.close hang and ScreenshotReplacer lifecycle`.

