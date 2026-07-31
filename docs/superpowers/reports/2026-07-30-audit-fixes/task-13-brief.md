### Task 13: «Deffered» → «Deferred» в демо

**Files:**
- Rename: `example/scopo_demo/lib/home/demos/i_deffered_closing/` → `i_deferred_closing/` (и файл `deffered_closing_demo.dart` → `deferred_closing_demo.dart`)
- Modify: класс `DefferedClosingDemo` → `DeferredClosingDemo`, лейбл вкладки в `example/scopo_demo/lib/home/home.dart:29` `'Deffered closing'` → `'Deferred closing'`

- [ ] **Step 1:** `git mv` + переименование класса + правка импортов/лейбла; `grep -rin deffered example/` → 0.
- [ ] **Step 2:** `flutter analyze` в scopo_demo → 0. Коммит: `fix Deferred spelling in demo`.

---

## Фаза 4 — документация и упаковка

