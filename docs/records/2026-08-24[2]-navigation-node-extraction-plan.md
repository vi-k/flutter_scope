# Вынос `NavigationNode` вторым пакетом: план

> **Состояние на 2026-08-24:** план написан, работа начата сразу после него.
> Итог — в отчёте `2026-08-24[3]-navigation-node-extraction-report.md`, если он
> уже есть; пока его нет, состояние работы смотри в `docs/handoff.md`.
> **Что это:** порядок работ по U7, вариант A′ — второй пакет в этом же
> репозитории, — и четыре решения владельца, на которых он стоит.
> **Связанные записи:** `2026-08-24[1]-navigation-node-boundary-design.md`
> (измерение и цена трёх вариантов), `2026-08-23[1]-consumer-review.md`
> (находка U7).

## Решения владельца, 2026-08-24

Все четыре приняты до начала работы; менять их по ходу нельзя, не сказав ему.

1. **Вариант A′** — второй пакет в этом же репозитории, `packages/navigation_node/`.
   Один репозиторий, один CI, две версии и две публикации.
2. **Имя пакета — `navigation_node`.** На pub.dev свободно (404 на
   `api/packages/navigation_node`, проверено 2026-08-24). Имя совпадает с
   именем класса и ищется по смыслу; `scopo_navigation` отвергнут — обещает
   связь, которой в коде нет.
3. **Пример нового пакета самостоятельный.** Единственная связь уроков со
   scopo — `ScopeModel<Ticket>` в `screen_scope.dart`, два вхождения; они
   заменяются на `InheritedWidget`. После этого в пакете нет ни одной ссылки на
   scopo — ни в коде, ни в примере, ни в его сьюте. Пару «нода + скоуп»
   показывает `example/scopo_demo`, где она и так есть.
4. **Снятие трёх имён из бареля кладётся в неопубликованную 0.11.0.** На
   pub.dev сейчас 0.10.0, а у `0.x` минорный бамп и есть слот ломающих правок:
   0.10.0 → 0.11.0 уже такой. Отдельной 0.12.0 не заводим.

## Что двигается

| откуда | куда |
| --- | --- |
| `lib/src/utils/navigation_node/navigation_node.dart` (655 строк) | `packages/navigation_node/lib/src/navigation_node.dart` + барель `lib/navigation_node.dart` |
| `test/navigation_node_test.dart` (1907 строк, 43 теста) | `packages/navigation_node/test/` |
| `example/navigation_node/` (13 файлов, 1649 строк, 17 тестов) | `packages/navigation_node/example/` |
| раздел `## NavigationNode` из `doc/utils.md` (строки 75–178) | `README.md` нового пакета |
| раздел «One node per tab» из `README.md` (712–755) | туда же |
| зеркала шести файлов в `docs/ru/` | `docs/ru/packages/navigation_node/…` |

## Порядок работ

Каждый шаг оставляет дерево в состоянии, в котором гейт §6 либо проходит, либо
заведомо ещё не должен: **зелёными обязаны быть только коммиты**, а их три —
план, вынос целиком, документы.

### Шаг 0. Пробы, которые дешевле сделать до работы

- **`packages/` в архиве scopo.** Добавить `/packages/` в `.pubignore` и
  проверить `dart pub publish --dry-run`: нового пакета в списке файлов быть
  не должно.
- **path-зависимость наружу архива.** `example/scopo_demo` получает
  `navigation_node: path: ../../packages/navigation_node` — путь выходит за
  корень публикуемого пакета. Проверить, что дай-ран по-прежнему даёт 0
  предупреждений. **Если предупредит** — решение владельца, а не обход
  молчком.
- **Имя примера.** Пример сейчас сам называется `navigation_node`
  (`publish_to: none`); внутри пакета того же имени это самоссылка.
  Переименовать в `navigation_node_example`.

### Шаг 1. Каркас нового пакета

`pubspec.yaml` (имя, описание про вложенную навигацию и системный «назад»,
версия `0.1.0`, `repository`/`homepage` на этот репозиторий, топики),
`README.md`, `CHANGELOG.md`, `LICENSE` (копия MIT), `analysis_options.yaml`
(копия корневого — правила те же), `.pubignore` (`/test/` по той же причине,
что и в scopo).

### Шаг 2. Код

`git mv` файла, барель `lib/navigation_node.dart` с библиотечным дартдоком,
снять `{@category utils}` (тема `utils` осталась в scopo), убрать строку
экспорта из `lib/scopo.dart`.

### Шаг 3. Сьюта

`git mv` теста, импорт `package:scopo/scopo.dart` → `package:navigation_node/navigation_node.dart`,
свой `test/flutter_test_config.dart` (leak-трекер) — копия корневого.

### Шаг 4. Пример

`git mv` каталога, `screen_scope.dart` на `InheritedWidget`, `pubspec.yaml`
примера: имя `navigation_node_example`, зависимость `navigation_node: path: ../`,
scopo — вон. Прогнать его 17 тестов.

### Шаг 5. Сторона scopo

- `example/scopo_demo` получает зависимость на новый пакет и импорт в пяти
  файлах;
- `doc/utils.md` — раздел вынут, строка таблицы указывает на пакет;
- `doc/debug.md:183` — упоминание проверить и поправить;
- `README.md` — пункт «Also in the box», раздел «One node per tab» и пункт в
  «Examples» уходят; остаётся строка, куда переехало;
- `CHANGELOG.md`, раздел 0.11.0 — ломающая строка со ссылкой на новый пакет;
- `.gitignore` — `/packages/navigation_node/pubspec.lock` (библиотека, лок не
  коммитим), лок примера коммитим.

### Шаг 6. Зеркала и проверки

- `docs/ru/packages/navigation_node/README.md` и
  `docs/ru/packages/navigation_node/example/README.md` — новые зеркала;
- `docs/ru/doc/utils.md`, `docs/ru/README.md`, `docs/ru/doc/debug.md`,
  `docs/ru/example/README.md`, `docs/ru/example/scopo_demo/README.md` — правки
  под переезд; старое зеркало `docs/ru/example/navigation_node/README.md`
  переезжает;
- `docs/ru/check.sh` и `stamp.sh` учатся путям `packages/*/README.md` и
  `packages/*/example/README.md`;
- `.github/workflows/ci.yml` — `pub get` и `analyze` для `packages/*/`,
  сьюта нового пакета, его дай-ран публикации, и `example/navigation_node`
  меняется на новый путь;
- **`AGENTS.md` §6** — гейт стал больше на один пакет; в нём это должно быть
  написано, иначе следующий агент прогонит половину.

### Шаг 7. Гейт

Восемь команд §6 в корне плюс своя четвёрка в новом пакете: `flutter test`,
`flutter analyze`, `dart format --set-exit-if-changed lib test`,
`dart doc --dry-run`, `dart pub publish --dry-run`.

### Шаг 8. Документы

Вердикт по U7 в самой находке (`AGENTS.md` §4), отчёт
`2026-08-24[3]-…-report.md`, `docs/handoff.md` — состояние, числа и порядок
публикации.

## Чего этот план не делает

- **Не публикует.** Ни `navigation_node`, ни scopo 0.11.0 — публикация только
  по явной просьбе владельца (`AGENTS.md` §5). Порядок, когда он решит:
  **сначала `navigation_node` 0.1.0, потом scopo 0.11.0**, иначе строка
  миграции в `CHANGELOG.md` две минуты будет обещать пакет, которого нет.
- **Не трогает U3.** Три имени уходят из бареля вместе с кодом, а не в порядке
  разделения барелей; остальные 99 остаются как есть.
