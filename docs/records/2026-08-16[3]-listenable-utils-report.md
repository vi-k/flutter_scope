# Волна 3 чистки ревью: утилиты `listenable`

> **Состояние на 2026-08-16:** сделано и смержено в `main` одним коммитом.
> **Что это:** отчёт о закрытии P2 №11, №12, №13 и P3 №18 из полного
> предвыпускного ревью.
> **Связанные записи:** `2026-08-14[10]-project-review.md` (сами находки),
> `2026-08-16[1]-cleanup-completeness-report.md`,
> `2026-08-16[2]-scope-data-and-selectors-report.md`.

## Что объединяет находки

Все четыре — о подписке на `Listenable`: кто ею владеет, когда её надо
переоформить и что означает `compare`. Три первых оказались одной ошибкой в трёх
местах — **равенство спутали с тождеством или с актуальностью**, — четвёртая
чисто документационная.

## P2 №11 — равная, но не та же модель

`_ScopeNotifierElement.update` решал через `!=`:

```dart
if (widget.value != newWidget.value) {
  widget.value?.removeListener(notifyDependents);
  newWidget.value?.addListener(notifyDependents);
}
```

Listener принадлежит объекту, который держит список listener-ов. Две модели,
равные по `==`, — это всё равно два списка. `ScopeNotifier.value` с моделью,
равной прежней, но другой, оставлял listener на брошенной: уведомления новой
пропадали, притом что `model` уже возвращал новую. Документация конструктора
обещает обратное — «A later build may hand it a different one; the subscription
moves with it».

Стало `!identical(...)`. Для владеющего режима поведение не меняется: там оба
`value` — `null`.

Тест `moves the subscription to an equal but different model` с фикстурой
`_NamedCounter`, у которой равенство по имени. Мутация обратно на `!=` роняет
1 тест.

## P2 №12 — `ListenableSelector` не замечал новый `selector`/`compare`

`didUpdateWidget` переподписывался только при смене `listenable`. Родитель,
передавший над тем же источником новое замыкание, продолжал получать прежнее:
`selector` считал не то, а `compare` отвечал не так.

Условие расширено до трёх сравнений по тождеству — `listenable`, `selector`,
`compare`. Переподписка заодно перечитывает значение, поэтому ближайшая сборка
показывает то, что новый селектор даёт сейчас.

Два теста: `follows a new selector on the same listenable` (селектор меняется на
`value * 10` — до правки виджет продолжал показывать старое) и `follows a new
compare on the same listenable` (compare «ничего никогда не менялось» сменяется
на умолчание). Мутация обратно на одно сравнение роняет 2 теста.

## P2 №13 — упавший селектор оставлял недоступный listener

```dart
addListener(handle);

return subscription =
    ListenableSelectSubscription._(this, handle, selector(this));
```

Первое значение читалось **после** регистрации. Селектор, упавший на этом первом
чтении, оставлял за собой:

- listener на notifier — а подписку вызывающий не получил, снять её нечем;
- неприсвоенное `late final subscription`, к которому следующее уведомление
  обращалось через `handle`, — то есть `LateInitializationError` поверх исходной
  ошибки.

Порядок перевёрнут: значение читается и подписка создаётся до `addListener`.
`addListener` слушателя не зовёт, поэтому присвоение гарантированно раньше
любого уведомления.

Тест `a selector that fails on the first read leaves nothing behind`: перехватив
`FlutterError.onError`, проверяет и что notifier ничего не слушает, и что
следующее уведомление ничего не сообщает. Мутация обратно на прежний порядок
роняет 1 тест.

## P3 №18 — документация рекомендовала обратный предикат

`compare:` отвечает на вопрос «изменилось ли», и `true` означает «да». Dartdoc
`CompareUtils.identical` при этом предлагал себя как «comparison to pass as
`compare:` for a value that is replaced rather than mutated» — то есть ровно
наоборот: тот же объект сошёл бы за изменение, а замена прошла бы незамеченной.

Рекомендация переехала к `notIdentical`. Заодно исправлены два источника той же
путаницы, которые ревью не называло, но из которых она и растёт:

- пример в dartdoc `Listenable.select` показывал
  `compare: (previous, current) => identical(previous, current)`;
- текст там же говорил «compared using the operator `==`», хотя проверка —
  `!=`; та же ошибка была в `ListenableSelector.compare` («`==` when omitted»).

Исправлены `doc/j_utils.md` и русское зеркало.

**Кода правка не потребовала: `notIdentical` всегда вёл себя правильно.** Тест
`notIdentical is the compare for a value that is replaced` поэтому не «сначала
красный», а закрепляющий: он превращает рекомендацию из текста в проверяемое
утверждение. При его написании фикстура сперва сравнивала два `const _Box(1)` —
канонизация констант делает их одним объектом, и тест падал по своей вине, а не
по вине кода.

## Проверки

Полный гейт из восьми команд `AGENTS.md` §6 на закреплённом тулчейне:
**191 тест зелёный**, `analyze` чист в корне и во всех трёх примерах, формат без
изменений, `dart doc` — 0 warnings, 0 errors, `dart pub publish --dry-run` —
0 warnings, переводы актуальны (14).

## Что осталось

7 находок: 5 P2 (№6, №7, №10, №14, №15) и 2 P3 (№16, №17).
