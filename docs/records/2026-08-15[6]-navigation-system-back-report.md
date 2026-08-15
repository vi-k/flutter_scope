# Системный back во вложенном NavigationNode — отчёт

> **Состояние на 2026-08-15:** реализовано в `45aa808`, затем пересмотрено.
> Оба упомянутых здесь review шли по ветке `onPop == null` — единственной, что
> была покрыта тестами; третье, независимое, нашло на ветке `onPop` две
> регрессии волны, и следующая волна их закрыла, заменив `NavigatorPopHandler`
> собственным диспетчером. См.
> `2026-08-15[9]-navigation-system-back-audit-report.md` и
> `2026-08-15[10]-navigation-onpop-regressions-report.md`.
> **Что это:** отчёт о TDD-исправлении P1 №2 полного review — системный back
> теперь обрабатывается вложенным navigator раньше внешнего route.
> **Связанные записи:** `2026-08-15[4]-navigation-system-back-design.md`,
> `2026-08-15[5]-navigation-system-back-plan.md`,
> `2026-08-15[9]-navigation-system-back-audit-report.md`,
> `2026-08-14[10]-project-review.md`.

## Причина

`NavigationNode` строил внутренний `_NodeNavigator`, но внешний `PopScope`
регистрировался на enclosing `ModalRoute`. Системный back начинался у корневого
navigator и не вызывал `_NodeNavigator.maybePop()`: pushed route или dialog
внутри узла оставался открытым, а внешний route мог быть снят.

`NavigatorPopHandler<Object?>` — штатный Flutter 3.29.0 dispatcher для этого
случая. Он получает `NavigationNotification` от дочернего navigator и
перехватывает системный back только когда внутренний стек способен его
обработать. Но первый вариант выявил второй уровень: Flutter передаёт
`onPopInvokedWithResult(false, …)` каждому `PopEntry` текущего `ModalRoute`.
Прежний внешний `PopScope` принял это за собственный отказ и переслал pop
родителю, поэтому внешний экран исчезал уже после корректного закрытия
внутреннего route.

Внешний callback теперь выходит, когда `_navigator.canPop()`: обработкой
занимается inner `NavigatorPopHandler`. Когда внутреннему navigator больше
нечего закрывать, продолжают работать прежние `onPop`, `isRoot` и
local-history hook.

## TDD и review

Три widget-регрессии через `tester.binding.handlePopRoute()` дали RED на
исходном коде: system back оставлял pushed `MaterialPageRoute`, inner dialog и
route root node открытыми. Минимальная обёртка с guard дала GREEN, 8/8 в
целевом файле. Временное удаление только `NavigatorPopHandler` вновь дало RED
во всех трёх сценариях; после восстановления — GREEN.

Первый независимый reviewer нашёл Important дефект: прямой
`_navigator.pop(result)` принудительно обходит внутренний
`PopScope(canPop: false)`. Новый реальный guarded-route тест подтвердил RED —
защищённая страница исчезала при system back, тогда как остальные восемь
navigation-тестов проходили. Вызов заменён на
`_navigator.maybePop(result)`; целевой файл стал зелёным, 9/9. Повторный
independent review проверил diff и поведение Flutter 3.29.0, не нашёл
материальных замечаний и дал verdict Ready.

## Документация и проверки

CHANGELOG и английская страница utilities теперь описывают приоритет внутреннего
navigator; русский перевод обновлён осмысленно, затем `stamp.sh` поставил новый
blob-хеш.

| проверка | результат |
| --- | --- |
| `fvm flutter test` | **155/155 зелёные** |
| root `fvm flutter analyze` | `No issues found!` |
| analyze обоих `example/*` | `No issues found!` в каждом |
| `fvm dart format --set-exit-if-changed lib test` | 76 файлов, 0 changed |
| `fvm dart doc --dry-run` | 0 warnings, 0 errors |
| `sh docs/ru/check.sh` | 13 актуальных зеркал |
| `fvm dart pub publish --dry-run` | 0 warnings в clean temporary clone |

Временный clone создан от кода final amended commit до добавления этого
report-record и финального обновления handoff. Это точный publishable набор:
`docs/` исключён `.pubignore`; проверка не зависит от стороннего untracked
`.claude/` основного checkout.

## Границы волны

P2 №14 (повторный и поздний async `onPop`) и P2 №17 (изменение
`navigatorKey`) не менялись. Следующая исходная находка по порядку — P1 №3:
частично созданная зависимость должна вызывать зарегистрированный disposer
после ошибки или отмены инициализации.
