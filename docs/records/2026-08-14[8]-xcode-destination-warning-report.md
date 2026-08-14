# Почему Xcode видит два совпавших macOS destination

> **Состояние на 2026-08-14:** расследование закончено, дефекта в scopo нет,
> код пакета и демо не менялся. Warning признан косметикой Flutter 3.29.0 на
> современном Xcode; пункт удалён из бэклога.
> **Что это:** разбор warning о выборе первого из двух совпавших macOS
> destinations (`arm64` и `x86_64`) при сборке `example/scopo_demo`.
> **Связанные записи:** `2026-08-14[7]-release-run-hang-report.md` — соседний,
> но независимый дефект Flutter tools в release-режиме.

## Что воспроизведено

На Apple Silicon (`uname -m` — `arm64`) с Xcode 26.5 и закреплённым Flutter
3.29.0 команда release-сборки печатает:

```text
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:…, name:My Mac }
{ platform:macOS, arch:x86_64, id:…, name:My Mac }
```

Обе записи описывают тот же физический Mac и отличаются только архитектурой.
Xcode выбирает первую запись — нативный для машины `arm64` destination.
Сборка при этом успешно завершается и приложение запускается.

## Откуда берётся неоднозначность

Flutter 3.29.0 в `packages/flutter_tools/lib/src/macos/build_macos.dart`
жёстко передаёт Xcode:

```text
-destination platform=macOS
```

Селектор задаёт платформу, но не архитектуру и не generic destination. Xcode
26.5 на ARM Mac с доступной Rosetta сопоставляет ему две возможности —
`arm64` и `x86_64` — поэтому предупреждает, что возьмёт первую.

Прямой `xcodebuild -showBuildSettings` с тем же широким destination повторил
warning. Два уточнённых варианта его не печатают:

```text
-destination platform=macOS,arch=arm64
-destination generic/platform=macOS
```

Это подтверждает, что источник — только недостаточно точный аргумент Flutter
tools, а не настройки Runner, CocoaPods или scopo.

## Почему выбор не портит release-продукт

Destination определяет цель операции Xcode, но release-настройки проекта
остаются многоархитектурными:

```text
ARCHS = arm64 x86_64
ONLY_ACTIVE_ARCH = NO
HOST_ARCH = arm64
NATIVE_ARCH = arm64
```

Явный `platform=macOS,arch=arm64` и generic destination дали тот же набор
`ARCHS = arm64 x86_64`. Реальный результат проверен через `file`: все четыре
исполняемых Mach-O внутри собранного `.app` содержат обе архитектуры:

- `Contents/MacOS/scopo_demo`;
- `App.framework/Versions/A/App`;
- `FlutterMacOS.framework/Versions/A/FlutterMacOS`;
- `shared_preferences_foundation.framework/Versions/A/shared_preferences_foundation`.

Следовательно, «Using the first» не означает, что x86_64-срез выброшен из
release-приложения. На ARM Mac Xcode выбирает нативную цель для операции, а
сама операция продолжает выпускать universal product.

## Исправление upstream

Flutter уже исправил ровно этот warning в
[`flutter/flutter#165996`](https://github.com/flutter/flutter/pull/165996),
см. commit `742141a8f3b9` от 2025-05-26. Новый Flutter tools выбирает:

- для debug — `platform=macOS,arch=<host architecture>`;
- для profile/release — `generic/platform=macOS`, потому что эти сборки
  многоархитектурные.

Первый стабильный тег, содержащий commit, — Flutter 3.35.0. Установленные
локально Flutter 3.44.4 и stable уже содержат эту логику.

## Решение для scopo

Код и Xcode-проект не менять. Проверки пакета намеренно идут на заявленном
полу Flutter 3.29.0, поэтому warning от старого Flutter tools ожидаем. Его
подавление в проекте скрывало бы внешнюю косметическую проблему и создавало
бы расхождение с типовой сборкой потребителя.

При работе на Flutter 3.35.0 и новее warning исчезает за счёт upstream-правки.
Переходить на новый SDK только ради этого сообщения не требуется.
