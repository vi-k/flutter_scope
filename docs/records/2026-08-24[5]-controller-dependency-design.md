# `controller()`: контроллер как узел дерева зависимостей

> **Состояние на 2026-08-24:** выполнено целиком и смержено в `main`. Два
> расхождения с дизайном, оба ниже названы `controller()` — так, как он был
> написан здесь и одобрен изначально:
>
> - метод и поле `controller` столкнулись именами в `example/scopo_demo`
>   (`FakeController controller` — обычный класс, даже не `ScopeController`),
>   обнаружено корневым `flutter analyze`. Решение владельца — переименовать
>   поле демки (`fakeController`), не метод;
> - тем же вечером владелец передумал и попросил переименовать сам метод в
>   `controllerDep` — короче со столкновением поля-с-таким-же-именем не
>   борется в принципе, но читается яснее рядом с `dep`. Правка внесена
>   вторым коммитом поверх первого, во всех местах, где ниже написано
>   `controller()`/`controller(name, create)`, теперь стоит `controllerDep`.
>
> Третий тест плана §6 сперва написан не был, и шапка при этом говорила
> «выполнено целиком» — поймано ревью правки, дописан следом. Он же показал,
> что **§3 этого дизайна ошибался в одном**: отмена обхода не бросает
> начатый инициализатор, а дожидается его. Разбор `controllerDep` при этом
> верен, но не по той причине, что здесь написана, — см. «Расхождение» в
> конце.
>
> Гейт §6 пройден целиком, тестов 421 → 424.
> **Что это:** дизайн нового билдера `controllerDep()` (в тексте ниже —
> `controller()`, см. состояние) в `ScopeAutoDependencies` — четвёртого рядом
> с `dep()`/`sequential()`/`concurrent()` — оборачивающего `ScopeController`
> в узел дерева зависимостей.
> **Связанные записи:** нет.

## 1. Зачем

Владелец спросил, можно ли добавить, наряду с `dep()`, что-то для
автоматической инициализации контроллеров `AsyncControllerScope`
(`ScopeController`). У `ScopeController` уже есть ровно та форма, которую
ждёт `ScopeDependencyHandle`: `init`/`onUnmount`/`dispose`, и отдельные
публичные `performInit()`/`performUnmount()`/`performDispose()` — дартдок
самого класса называет их «driven by hand», то есть уже рассчитанные на
вызов извне, не только скоупом-владельцем. Моста между двумя семействами
при этом нет: `ScopeAutoDependencies` (где живёт `dep()`) и
`AsyncControllerScope`/`ScopeController` — независимый код, ни один файл не
ссылается на другой (проверено `grep` в обе стороны).

Без моста контроллер, написанный для одного экрана
(`AsyncControllerScope<PlayerController>`), нельзя переиспользовать как одну
из веток дерева зависимостей другого скоупа — приходится либо вручную
повторять три строки регистрации (`handle.unmount = …`, `handle.dispose =
…`, `await controller.performInit()`), либо дублировать логику контроллера
в виде обычного `dep()`.

## 2. Форма

```dart
/// A single dependency backed by a [ScopeController].
///
/// The three lifecycle hooks are wired to the handle in the order the
/// "acquire, register, then carry on" rule asks of a hand-written `dep`:
/// nothing between creating the controller and registering its teardown can
/// throw or suspend, because creating it does neither.
ScopeDependency controller<T extends ScopeController>(
  String name,
  T Function() create,
) =>
    dep(name, (handle) async {
      final controller = create();
      handle.unmount = controller.performUnmount;
      handle.dispose = controller.performDispose;
      await controller.performInit();
    });
```

Живёт в `scope_auto_dependency.dart`, рядом с `dep`/`sequential`/
`concurrent` — тот же класс, `ScopeAutoDependencies`, никакого нового типа.

Использование — тот же идиом, что у `dep()`: фабрика пишет в поле
контейнера сама.

```dart
concurrent('user', [
  controller('player', () => player = PlayerController(api: apiClient)),
  dep('settings', (dep) async { /* … */ }),
]),
```

## 3. Почему порядок безопасен по построению, а не по обещанию

`performUnmount()` смотрит на `_mounted`, который выставляет только
`performInit()`; `performDispose()` не смотрит ни на что — оба идемпотентны
и безопасны, даже если `performInit()` ни разу не был вызван
(`lib/src/scope/async_controller_scope/scope_controller.dart:39-58`). Значит
регистрация `handle.unmount`/`handle.dispose` **до** `await
controller.performInit()` не оставляет окна: если инициализация оборвётся
раньше, чем до неё дойдёт, разбирать нечего — контроллер ничего не занял.

Подписи совпадают дословно, приводить или заворачивать нечего:
`ScopeDependencyHandle.unmount` — `void Function()?`, `performUnmount` —
`void Function()`; `.dispose` — `FutureOr<void> Function()?`,
`performDispose` — `Future<void> Function()` (`Future<void>` — подтип
`FutureOr<void>`).

## 4. Что не меняется

- `ScopeController`/`AsyncControllerScope` не узнают о существовании
  `ScopeAutoDependencies` — зависимость односторонняя, только новый метод
  использует `ScopeController`;
- дерево зависимостей ведёт себя как обычно: прогресс, таймауты,
  `autoDisposeOnError`, порядок разбора групп — `controller()` в этом ничего
  не меняет, потому что это просто `dep()` с готовой инициализацией внутри.

## 5. Документация

- `doc/full_scope.md` — абзац рядом с описанием `dep`/`sequential`/
  `concurrent`, четвёртым пунктом списка;
- `README.md` — предложение в разделе `AsyncControllerScope` или в
  «1. Dependencies», объясняющее, что тот же `ScopeController` годится и
  туда, и туда — по правилу «новое публичное имя требует зачем в README»;
- зеркала `docs/ru/` в тех же коммитах, следом `sh docs/ru/stamp.sh`;
- строка в `CHANGELOG.md`, раздел текущей версии — правка аддитивная, не
  ломающая.

## 6. Проверка

Тест сначала (`AGENTS.md` §8). Новая группа тестов, показывающая:

1. порядок вызовов — `create` → `performInit` (await) → (при разборе)
   `performUnmount` → `performDispose`;
2. отказ `performInit` даёт тот же путь ошибки, что у любого `dep()` —
   попадает в `flattenDependenciesWithErrors()` и роняет свою группу так же;
3. разбор при отмене на середине `performInit` — `mounted` контроллера
   становится `false`, `performDispose` освобождает то, что было
   зарегистрировано.

Гейт: тронуты `lib/`, `test/`, `doc/`, `docs/ru/`, `CHANGELOG.md` — все
восемь команд `AGENTS.md` §6.

## 7. Расхождение: чем §3 ошибался

Дописано 2026-08-24, после того как ревью поймало ненаписанный третий тест
плана §6. Текст выше оставлен как был — он исторический.

**Отмена обхода не бросает начатый инициализатор, а дожидается его.** §3
говорит про «окно», которого не оставляет регистрация до `await`, и подводит
к тому, что отмена посреди `performInit` застаёт контроллер поднятым и никем
не удерживаемым. Написанный тест показал другое: `subscription.cancel()`
ждёт, пока `performInit` доработает, и только потом `finally` генератора
`init()` зовёт `onUnmount()` и `dispose()`. В журнале это видно прямо —
`['init', 'init finished', 'onUnmount', 'dispose']`, и первая версия теста,
написанная по §3 (ожидала отсутствия `init finished`), на этом и упала.

**Вывод §3 при этом верен, а обоснование — нет.** Регистрация до `await`
нужна, но не отмене: отмена зарегистрировала бы и позже, раз она дожидается
инициализатора. Нужна она **отказу** — `performInit`, бросивший до
регистрации, уносит контроллер, о котором никто не знает. Это и показывает
проверка нагруженности, и она же разделяет два теста:

| мутация | какой тест краснеет |
| --- | --- |
| регистрация после `await` | только тест про отказ |
| снятая регистрация `handle.dispose` | только тест про отмену |

То есть три теста стерегут три разных свойства, и ни один из них не лишний;
но написать «тест про отмену проверяет порядок регистрации» было бы неправдой
— он проверяет, что на пути отмены контроллер вообще освобождается.
