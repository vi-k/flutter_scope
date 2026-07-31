### Task 16: example/README.md — устранить дрейф (это страница Example на pub.dev)

pub.dev не находит ни один из example-app'ов автоматически (они на уровень глубже, чем ищет pana) и рендерит `example/README.md` — рукописную копию minimal, которая разъехалась и не компилируется.

**Files:**
- Modify: `example/README.md`

- [ ] **Step 1:** заменить вложенный код точной копией актуального `example/minimal/lib/main.dart` (целиком, включая блок логирования строк 1-33 — сейчас он отсутствует, и logging невидим на pub.dev; включая `@override void unmount() {}`, `final class`, `covariant String? progress`).
- [ ] **Step 2:** единственный русский dartdoc в minimal (`example/minimal/lib/main.dart:59` `/// Метод инициализации зависимостей.`) перевести на английский в самом `main.dart` — копия в README подтянется.
- [ ] **Step 3:** сохранить ссылки на оба приложения; ссылку на `scopo_demo` поднять выше и подписать («9 interactive demos»). Коммит: `sync example README with minimal app`.

