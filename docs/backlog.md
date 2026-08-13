# Бэклог

> Записи владельца: что хочется сделать. Пишет владелец, агент читает,
> предлагает взять пункт в работу и удаляет выполненное (правила — в
> `AGENTS.md`, раздел 3). Состояние проекта — в `docs/handoff.md`.

## Код

- `example` для `ScopeWidgetCore`.

## Документация

- Написать нормальную документацию.
- Описать все примеры.
- Заполнить оставшиеся 7 заглушек `doc/*.md`: `a_base`, `b_scope_widget`,
  `c_scope_model`, `d_scope_notifier`, `e_async_scope`, `f_async_data_scope`,
  `g_lite_scope` (`h_scope` и `i_debug` написаны в 0.10.0).
- Скриншоты для pub.dev: секция `screenshots:` в `pubspec.yaml` отсутствует.
- Категории dartdoc: слои скоупов разобраны, остались 15 утилит из
  `lib/src/utils/**` (listenable-хелперы, `NavigationNode`, `ProgressIterator`,
  `CompareUtils`, `IsBuildingExtension`, `ScreenshotReplacer`) — они не входят
  ни в одну из девяти категорий. Решить: заводить им свою категорию со своей
  страницей или отнести к `base`.
