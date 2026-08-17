# debug

> Перевод `doc/debug.md` (blob `e8f8d0f0a387a9672fdd9bbea4ea90edfcb756e6`).
> Правится в том же коммите, что и оригинал; проверка — `sh docs/ru/check.sh`.

Журнал и глобальные настройки пакета. Всё на этой странице статическое и живёт в
`ScopeConfig`, поэтому обычное место для настройки — `main()`, до `runApp`.

## Уровни

Журнал по умолчанию выключен: `ScopeConfig.logger.level` равен
`ScopeLogLevel.off`. Присвоение более низкого порога включает все уровни, чьё
значение больше или равно ему.

```dart
void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  runApp(const App());
}
```

`ScopeLogLevel` собирает пороги, которыми пользуется пакет. Это обычные
константы `int` (те же `Levels` из `logger_builder`), так что `level` примет и
промежуточное значение.

| Константа | Значение | Что пишет пакет |
| --- | --- | --- |
| `ScopeLogLevel.all` | 0 | самый низкий возможный порог: всё |
| `ScopeLogLevel.verbose` | 400 | зарегистрирован, но пакетом не используется |
| `ScopeLogLevel.debug` | 500 | весь жизненный цикл, шаг за шагом |
| `ScopeLogLevel.info` | 800 | вехи асинхронного скоупа |
| `ScopeLogLevel.error` | 1000 | провалы инициализации и утилизации |
| `ScopeLogLevel.off` | 2000 | самый высокий возможный порог: ничего |

`info` — разумное значение по умолчанию для приложения: сообщает
`initialize…`/`initialized`, значения прогресса, `dispose…`/`disposed` и отмену
прерванной инициализации.

`debug` — то, что включают, когда скоуп подвисает, инициализируется в
неожиданном порядке или утилизируется слишком поздно. Сверх сообщений уровня
`info` он рассказывает о подготовке к инициализации и утилизации, об ожидании
`scopeKey`, об ожидании дочерних скоупов и о каждой зависимости
`ScopeAutoDependencies` в момент её инициализации или утилизации.

`error` сообщает `initialization failed`, `disposal failed` и ошибки,
возникшие при утилизации зависимостей, — каждую с её `error` и `stackTrace`.
Учтите, что скоуп и без журнала отдаёт ошибки инициализации в `buildOnError`, а
таймауты — в `FlutterError.reportError`, так что выключенный журнал никогда не
прячет ошибку целиком.

## Вывод

У каждого уровня свой публикатор, поэтому формат и назначение можно заменить
поуровнево:

```dart
ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
  format: ScopeLogger.defaultFormat,
  output: debugPrint,
);
```

`ScopeLogFormatter` — это `ScopeLogPublisher`, собранный из двух функций:
`format` превращает `ScopeLog` во что-нибудь (обычно в `String`), а `output`
получает результат. Присвоение `ScopeConfig.logger.publisher` вместо
`ScopeConfig.logger[level].publisher` заменяет публикатор сразу всех уровней. По
умолчанию каждый уровень форматирует через `ScopeLogger.defaultFormat` и печатает
через `print`.

`ScopeLog` несёт `timestamp`, `path` породившего его логгера, `message`,
числовой `level` с его `levelName` и `shortLevelName`, а также необязательные
`error` и `stackTrace`. `ScopeLogger.defaultFormat` раскладывает это так:

```text
[d] scopo | TestDependencies(#25f53) | progress: dep1 (1/10)
[i] scopo | CounterScope(#4e0b7) | initialized
[e] scopo | CounterScope(#4e0b7) | initialization failed: Exception: no network
```

Путь начинается с имени корневого логгера (`scopo`) и получает по сегменту на
каждый вложенный логгер — для скоупа это тип виджета с коротким хешем или с его
`tag`, если тег задан. Сегменты склеиваются через `ScopeLogger.pathSeparator`
(по умолчанию ` | `; присвойте его на `ScopeConfig.logger`, и созданные после
этого подлоггеры его унаследуют). За сообщением идёт `: <error>`, если событие
несёт ошибку, и стек вызовов отдельной строкой, если он непустой.

`ScopeLogFn` — сигнатура четырёх методов журналирования у `ScopeLogger` (`v`,
`d`, `i`, `e`): сообщение плюс необязательные `error` и `stackTrace`. Сообщение
имеет тип `Object?`, и переданный вместо него колбэк вызывается, только когда
уровень включён, — поэтому вызовы внутри пакета выглядят как
`_log.d(() => 'progress: $path')`.

`ScopeLevelLogger` — объект за `ScopeConfig.logger[level]`: он держит `name`,
`shortName` и `publisher` своего уровня.

### Фильтрация и переписывание

Трансформер выполняется для каждой записи каждого уровня прямо перед
публикацией. Возврат `null` выбрасывает запись — так отсекают шумные пути, не
выключая уровень целиком:

```dart
ScopeConfig.logger.transformer = (log) =>
    log.path.contains('AnimationScope') ? null : log;
```

Его сигнатура — `ScopeLogTransformer`. Подлоггеры наследуют трансформер так же,
как наследуют `level` и публикаторов, поэтому присвоение на
`ScopeConfig.logger` покрывает весь пакет. Трансформер, который бросил
исключение, выбрасывает запись, а не публикует её непреобразованной, и сообщает
об ошибке в текущую зону.

### Цвета по уровням

Приём, которым пользуются оба примера, — свой ANSI-принтер на уровень:

```dart
import 'dart:io';

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;
import 'package:scopo/scopo.dart';

void setLogPrinter(int level, ansi.Color foreground) {
  final printer = ansi.Printer(
    ansiCodesEnabled: !Platform.isIOS,
    defaultStyle: ansi.Style(foreground: foreground),
  );

  ScopeConfig.logger[level].publisher = ScopeLogFormatter(
    format: ScopeLogger.defaultFormat,
    output: printer.print,
  );
}

void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  setLogPrinter(ScopeLogLevel.verbose, ansi.Color256.gray7);
  setLogPrinter(ScopeLogLevel.debug, ansi.Color256.gray12);
  setLogPrinter(ScopeLogLevel.info, ansi.Color256.rgb345);
  setLogPrinter(ScopeLogLevel.error, ansi.Color256.rgb400);

  runApp(const App());
}
```

Публикатор не обязан ничего форматировать: подойдёт любой
`ScopeLogPublisher` — так события собирают в список и проверяют в тестах.

## Таймауты

Четыре ожидания в жизненном цикле скоупа ограничены таймаутом, и все четыре
значения по умолчанию живут в `ScopeConfig`:

- `ScopeConfig.defaultScopeKeysTimeout` — сколько скоуп ждёт, пока предыдущий
  владелец освободит его `scopeKey`;
- `ScopeConfig.defaultInitCancellationTimeout` — сколько разбор ждёт отмены
  инициализации;
- `ScopeConfig.defaultDisposeAsyncTimeout` — сколько разбор ждёт `disposeAsync`,
  собственного освобождения скоупа;
- `ScopeConfig.defaultWaitForChildrenTimeout` — сколько скоуп ждёт утилизации
  дочерних скоупов, прежде чем утилизироваться самому.

Все четыре по умолчанию три секунды. `null` снимает ограничение, и скоуп ждёт
бесконечно. Истёкший таймаут не фатален: о нём сообщают через
`FlutterError.reportError`, после чего скоуп продолжает так, будто ожидание
удалось, — поэтому зависимость, которая никогда не завершает свою утилизацию,
вырождается в задержку плюс сообщение об ошибке, а не в дедлок.

Два средних меряются по настоящему времени, а не по часам той зоны, в которой
идёт разбор, — виджет-тест подменяет их фальшивыми. Зависания, ради которых эти
лимиты и нужны, живут дольше кадров, а скоуп обычно снимают между кадрами:
таймер, принадлежащий такой зоне, остался бы непогашенным к моменту, когда
дерева уже нет, а именно на этом `flutter_test` заканчивает тест.

Любой скоуп может переопределить все четыре значения для себя параметрами
`scopeKeyTimeout`, `initCancellationTimeout`, `disposeAsyncTimeout` и
`waitForChildrenTimeout` и заметить истечение через колбэки
`onScopeKeyTimeout`, `onInitCancellationTimeout`, `onDisposeAsyncTimeout` и
`onWaitForChildrenTimeout`. Чего скоуп не может для себя — снять ограничение:
`null` там означает «взять значение по умолчанию», а не «ждать сколько
понадобится». Снимают ограничение значениями `ScopeConfig` выше, и сразу для
всех скоупов.

## pauseAfterInitializationEnabled

`pauseAfterInitialization` — искусственная задержка между моментом, когда скоуп
стал готов, и моментом, когда показывают его поддерево; она существует, чтобы
индикатор загрузки провисел достаточно долго, чтобы его успели прочитать, а не
мигнул.

`ScopeConfig.pauseAfterInitializationEnabled = false` выключает все такие паузы
глобально, не трогая объявившие их виджеты. Ставьте это в настройке
виджет-теста или когда проходите инициализацию отладчиком.

## reset()

Перечисленные выше переключатели — пауза и четыре таймаута — глобальные и живут
дольше кода, который их менял: тест, поднявший таймаут и забывший вернуть его на
место, отдаёт следующему тесту другой пакет. `ScopeConfig.reset()` возвращает
все пять к умолчаниям:

```dart
void main() {
  tearDown(ScopeConfig.reset);
  …
}
```

`setUp` подходит не хуже и вдобавок покрывает тест, упавший до собственного
teardown. Логгер не трогается: это объект со своими издателями и
трансформером, а не переключатель, и заданный ему уровень — обычно и есть
смысл того прогона, ради которого его задавали.

## В тестах

Вся настройка для тестового набора — это порог плюс публикатор, направленный
туда, куда идёт вывод тестов:

```dart
void logInit() {
  ScopeConfig.logger.level = ScopeLogLevel.debug;
  ScopeConfig.logger.publisher = const ScopeLogFormatter(
    format: ScopeLogger.defaultFormat,
    output: print,
  );
}
```

Держите это включаемым по требованию: на `debug` один скоуп даёт с десяток
строк, и они хоронят причину падения теста. Между расследованиями —
`ScopeLogLevel.off`, и `ScopeConfig.pauseAfterInitializationEnabled = false`,
чтобы паузы не приходилось прокручивать кадрами.

Настройку настоящего приложения смотрите в
[example/minimal](https://github.com/vi-k/scopo/blob/main/example/minimal/lib/main.dart),
а демонстрацию, где рядом журналируется каждый вызов жизненного цикла каждого
семейства скоупов, — в
[example/scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo).
