# Бэклог

> Записи владельца: что хочется сделать. Пишет владелец, агент читает,
> предлагает взять пункт в работу и удаляет выполненное (правила — в
> `AGENTS.md`, раздел 3). Состояние проекта — в `docs/handoff.md`.

## Код

- `ScopeAutoDependenciesProgress` — добавить `name` (а `name` переименовать в
  `path`).
- `example` для `ScopeWidgetCore`.

## Тесты

- Одновременно `notifyDependents` и перестроение дерева сверху (`setState`).
- Проверить ребёнка с глобальным ключом: что он успешно перерегистрируется и
  фризит старого родителя.

## Документация

- Написать нормальную документацию.
- Описать все примеры.
- Заполнить оставшиеся 7 заглушек `doc/*.md`: `a_base`, `b_scope_widget`,
  `c_scope_model`, `d_scope_notifier`, `e_async_scope`, `f_async_data_scope`,
  `g_lite_scope` (`h_scope` и `i_debug` написаны в 0.10.0).
- Скриншоты для pub.dev: секция `screenshots:` в `pubspec.yaml` отсутствует.
- В категорию Scope не попадают `ScopeState`, `ScopeDependencyException`,
  `ScopeDependencyInfo`, `DepHelper`, `ScopeDependenciesExtension`,
  `ScopeDependencyExtension` — у них нет `{@category Scope}`. Аналогично
  проверить остальные 8 категорий.
