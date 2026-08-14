# План пояснения колбэков `ScopeModel`

> **Состояние на 2026-08-14:** план готов, выполнение не начато.
> **Что это:** пошаговый план правки английской страницы `ScopeModel`, её
> русского зеркала и состояния проекта.
> **Связанные записи:** `2026-08-14[1]-scope-model-callbacks-design.md`.
>
> **Для агентов-исполнителей:** ОБЯЗАТЕЛЬНЫЙ ДОПОЛНИТЕЛЬНЫЙ SKILL — использовать
> `superpowers:subagent-driven-development` или `superpowers:executing-plans`
> для выполнения плана по задачам. Ход отмечать чекбоксами (`- [ ]`).

**Цель:** объяснить, почему `ScopeModel.builder` получает контекст, а
`ScopeModel.dispose` — созданную модель.

**Устройство:** один абзац добавляется рядом с первым примером API, где вопрос
возникает у читателя. Английский оригинал и русское зеркало меняются вместе;
реализация и публичный API пакета не затрагиваются.

**Технологии:** Markdown, `docs/ru/stamp.sh`, `docs/ru/check.sh`, Flutter 3.29.0
и Dart 3.7.0 через `fvm`.

## Общие ограничения

- Публичные документы пишутся по-английски; зеркала в `docs/ru/` — по-русски.
- Перевод меняется в том же коммите, что и оригинал, после чего запускается
  `sh docs/ru/stamp.sh`.
- Из `docs/backlog.md` удаляется только выполненная запись владельца.
- `lib/`, публичный API и `CHANGELOG.md` не меняются.
- Перед завершением проходят все семь проверок из `AGENTS.md` §6 через
  Flutter 3.29.0 (`fvm`).
- В коммиты входят только перечисленные в соответствующем шаге файлы.

---

### Задача 1: Дополнить тематическую страницу и закрыть бэклог

**Файлы:**

- Изменить: `doc/c_scope_model.md`, сразу после первого примера
  `ScopeModel<Cart>`.
- Изменить: `docs/ru/doc/c_scope_model.md`, в том же месте зеркала.
- Изменить: `docs/backlog.md`, раздел «Документация».

**Интерфейсы:**

- Использует: существующие `ScopeModel.of`, `ScopeModel.select` и контракт
  жизненного цикла `ScopeModel`.
- Даёт: одинаковое объяснение сигнатур колбэков на двух языках и актуальный
  blob-хеш зеркала.

- [ ] **Шаг 1: добавить английский абзац после примера**

  Добавить текст:

  ```markdown
  `builder` deliberately receives only a context. That context belongs to the
  scope's element, so the model is already available through `ScopeModel.of`
  and `ScopeModel.select`, with the same lookup and subscription rules that
  descendants use. `dispose` runs at the other end of the lifecycle, outside a
  build; the element already owns the exact model it created, so it hands that
  instance to the callback directly instead of asking teardown code to look it
  up through the tree.
  ```

- [ ] **Шаг 2: добавить точный русский перевод**

  Добавить текст в соответствующее место зеркала:

  ```markdown
  `builder` намеренно получает только контекст. Этот контекст принадлежит
  элементу скоупа, поэтому модель уже доступна через `ScopeModel.of` и
  `ScopeModel.select` — с теми же правилами поиска и подписки, которыми
  пользуются потомки. `dispose` работает на другом конце жизненного цикла, вне
  сборки; элемент уже владеет ровно той моделью, которую создал, и потому
  передаёт этот экземпляр колбэку напрямую, вместо того чтобы заставлять код
  утилизации искать его через дерево.
  ```

- [ ] **Шаг 3: обновить штамп и проверить зеркало**

  Выполнить:

  ```sh
  sh docs/ru/stamp.sh
  sh docs/ru/check.sh
  ```

  Ожидание: `docs/ru/check.sh` сообщает, что все 13 переводов актуальны.

- [ ] **Шаг 4: удалить выполненную запись из бэклога**

  Удалить только строки:

  ```markdown
  - В документации к `ScopeModel` не сказано, почему в builder не передаётся
    созданный объект, а в dispose передаётся.
  ```

- [ ] **Шаг 5: прогнать полный гейт**

  Выполнить по отдельности и сохранить фактические результаты для
  `docs/handoff.md`:

  ```sh
  fvm flutter test
  fvm flutter analyze
  (cd example/minimal && fvm flutter analyze)
  (cd example/scopo_demo && fvm flutter analyze)
  fvm dart format --set-exit-if-changed lib test
  fvm dart doc --dry-run
  fvm dart pub publish --dry-run
  sh docs/ru/check.sh
  ```

  Ожидание: 146 тестов зелёные; оба анализа и форматирование чистые; dartdoc и
  dry-run публикации без предупреждений; все 13 переводов актуальны.

- [ ] **Шаг 6: проверить и закоммитить пользовательский результат**

  Выполнить `git diff --check`, просмотреть `git diff` и добавить поимённо:

  ```sh
  git add doc/c_scope_model.md docs/ru/doc/c_scope_model.md docs/backlog.md
  git commit -m "docs: explain the ScopeModel callback signatures"
  ```

### Задача 2: Зафиксировать завершённое состояние

**Файлы:**

- Изменить: `docs/records/2026-08-14[1]-scope-model-callbacks-design.md`.
- Изменить: `docs/records/2026-08-14[2]-scope-model-callbacks-plan.md`.
- Изменить: `docs/handoff.md`.

**Интерфейсы:**

- Использует: хеш коммита результата и вывод полного гейта из задачи 1.
- Даёт: актуальный снимок проекта и исторические шапки с конечным состоянием.

- [ ] **Шаг 1: обновить исторические шапки**

  В design-записи указать, что работа сделана в коммите результата. В шапке
  этого плана указать тот же коммит и отметить выполнение; отметить выполненные
  чекбоксы задачи 1 и этой задачи по мере завершения.

- [ ] **Шаг 2: обновить `docs/handoff.md`**

  Удалить указания на незавершённую работу, записать хеш коммита результата и
  фактические итоги проверок. В «Что дальше» оставить три следующих кандидата:
  скриншоты pub.dev, example для `ScopeWidgetCore`, публикацию 0.10.0.

- [ ] **Шаг 3: проверить и закоммитить состояние**

  Выполнить `git diff --check`, `sh docs/ru/check.sh`, просмотреть `git diff` и
  добавить поимённо:

  ```sh
  git add docs/handoff.md \
    'docs/records/2026-08-14[1]-scope-model-callbacks-design.md' \
    'docs/records/2026-08-14[2]-scope-model-callbacks-plan.md'
  git commit -m "docs: record the ScopeModel explanation"
  ```
