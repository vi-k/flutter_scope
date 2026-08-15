# Терминальный неуспех `init()` и симметричная утилизация

> **Состояние на 2026-08-15:** реализовано и полностью проверено в единственном
> коммите на ветке `worktree-review-scope-init-after-mount` (база `772e8f0`).
> Закрывает три дефекта, найденные независимым ревью волны P1 №1, и добавляет
> диагностику подписки из хука инициализации.
> **Что это:** отчёт о fix-волне по итогам
> `2026-08-15[7]-scope-init-after-mount-audit-report.md`.
> **Связанные записи:** `2026-08-15[7]-scope-init-after-mount-audit-report.md`,
> `2026-08-15[1]-scope-init-after-mount-design.md`,
> `2026-08-15[3]-scope-init-after-mount-report.md`,
> `2026-08-14[10]-project-review.md`.

## Причина

Волна P1 №1 перенесла общий `init()` из конструктора элемента в первую сборку —
и вместе с этим завела сущность, которой раньше не было: элемент, чей
синхронный `init()` не удался, теперь **остаётся жить в дереве**. Раньше такой
элемент не создавался вовсе (`createElement()` бросал), поэтому ни один метод
элемента не обязан был уметь работать без модели.

Волна закрепила два правила, которые вместе и породили дефекты:

- **retry** — «бросил, следующая сборка повторит»;
- **`dispose()` только после успеха** — `unmount()` пропускал утилизатор при
  `_didInit == false`.

Первое правило берёт ресурсы заново, второе не отдаёт взятые. Ревью нашло три
следствия: незакрываемая запись у родителя (`activate()` регистрирует скоуп,
которого никто не снимет), вечно висящий `close()` (`_initCompleter` не
завершает никто) и повторный захват при retry.

Владелец выбрал вариант «терминальный неуспех + симметрия».

## Что сделано

**Три состояния вместо флага.** `ScopeWidgetElementBase` держит
`_InitPhase { pending, done, failed }` и запомненную пару
`(error, stackTrace)`. Первая сборка выполняет `init()` внутри error boundary
`ComponentElement.performRebuild()`; бросок переводит элемент в `failed`,
запоминает ошибку и пробрасывает её дальше. Каждая следующая сборка поднимает
**ту же** ошибку с её собственным stack trace — хук второй раз не зовут, и
`buildChild()` для несуществующего скоупа не выполняется.

**Симметрия «взял/отдал».** `unmount()` вызывает `dispose()` для всего, что не
`pending`, — включая неуспешную попытку. Утилизаторы семейств научены жить с
частичным состоянием:

- `_ScopeModelElementMixin.dispose()` — убран assert «есть disposer ⇒ есть
  модель»: неудачный `create` теперь законно не оставляет модели, а следующий
  pattern-match и так это учитывает;
- `ScopeNotifierElementBase` — новое поле `_didListen`: listener снимают только
  если его успели повесить (иначе геттер `model` сам бросил бы);
- `AsyncScopeElementBase._performAsyncDispose()` — завершает `_initCompleter`,
  когда async-фаза не стартовала: ждать было бы нечего и некого;
- `AsyncScopeElementBase.activate()` — скоуп без стартовавшей async-фазы не
  регистрируется у родителя: ему нечего и некогда будет отчитываться.

**Диагностика подписки из хука.** `ScopeContext._find` бросает `assert`, когда
`listen: true` запрошен из элемента, чей `init()` сейчас выполняется. Элемент
запоминается в библиотечной переменной `_debugInitializingElement`, которую
пишут только из `assert`, так что в release это ничего не стоит. Раньше такой
вызов падал сам собой (предка не было); после переноса в `build()` он начал
тихо полурабоать — зависимость регистрировалась, а прочитанное в хуке значение
устаревало навсегда.

**Устаревшие комментарии.** Три места в тестах всё ещё говорили, что
`_performAsyncInit()` стартует из `mount()`; теперь — из первой
`performRebuild()`.

## TDD и мутации

Шесть новых или переписанных сценариев, все сначала красные:

| тест | что закрепляет |
| --- | --- |
| `scope_widget`: `a failed init is not retried and is still cleaned up` | одна попытка, один захват, освобождение при снятии |
| `scope_widget`: `subscribing to a scope from init is rejected` | `assert` на `listen: true` из хука |
| `scope_model`: `does not run create again after it failed` | `create` не повторяется, снятие тихое |
| `scope_notifier`: `a failed create leaves nothing to unsubscribe from` | утилизатор не тянется к несозданной модели |
| `async_scope`: `never starts the asynchronous phase when the synchronous init failed` | async-фаза не стартует, `disposeAsync` не зовут |
| `async_scope`: `a scope whose synchronous init failed is not left registered with its parent` | родитель утилизируется, не выжидая таймаут |
| `lite_scope`: `completes for a scope whose synchronous init failed` | `close()` завершается |

Тест волны `retries a synchronous create failure on the next build` переписан в
`does not run create again after it failed`: он закреплял ровно то поведение,
от которого решено отказаться. Тест
`defers asynchronous initialization until the first successful sync init`
разделён на два — «не стартует после неуспеха» и «стартует один раз после
успеха», — потому что прежний соединял их через retry.

Шесть мутаций, по одной на каждую производственную правку, дали ожидаемый RED:
возврат retry (роняет три файла), возврат `if (_didInit)` в `unmount()`, снятие
guard-а в `activate()`, снятие завершения `_initCompleter`, отключение
`assert`-а и снятие `_didListen`. Ни одна правка не оказалась ненагруженной.

## Проверки

Полный гейт `AGENTS.md` §6 на Flutter 3.29.0 через fvm:

| проверка | результат |
| --- | --- |
| `fvm flutter test` | **157 тестов, все зелёные** |
| `fvm flutter analyze` (корень) | `No issues found!` |
| `analyze` в обоих `example/*` | `No issues found!` в каждом |
| `fvm dart format --set-exit-if-changed lib test` | 76 файлов, 0 changed |
| `fvm dart doc --dry-run` | 0 warnings, 0 errors |
| `sh docs/ru/check.sh` | переводы актуальны: 13 |

## Что осталось

Исходный P1 №3 («утечка частично созданной зависимости») не трогали: он про
асинхронный контейнер зависимостей, а не про синхронный хук. P1 №2 (системный
back мимо вложенного `Navigator`) идёт отдельной работой.
