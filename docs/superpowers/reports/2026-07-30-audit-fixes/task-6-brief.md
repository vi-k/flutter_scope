### Task 6: `ScopeNotifierBase.update` не подписывается на новый Listenable

`lib/src/scope/d_scope_notifier/scope_notifier_base.dart:82-89`: при смене `widget.value` старый слушатель снимается, а на новый вызывается `removeListener` вместо `addListener` — все `select`/`of(listen: true)` навсегда перестают обновляться.

**Files:**
- Modify: `lib/src/scope/d_scope_notifier/scope_notifier_base.dart:86`
- Test: Create `test/scope_notifier_test.dart`

- [ ] **Step 1: падающий widget-тест**

```dart
testWidgets('swapping ScopeNotifier.value re-subscribes', (tester) async {
  final first = ValueNotifier(0);
  final second = ValueNotifier(100);
  Widget app(ValueNotifier<int> v) => MaterialApp(
        home: ScopeNotifier<ValueNotifier<int>>.value(
          value: v,
          child: Builder(
            builder: (context) => Text(
              '${ScopeNotifier.of<ValueNotifier<int>>(context).value}',
            ),
          ),
        ),
      );
  await tester.pumpWidget(app(first));
  await tester.pumpWidget(app(second));
  second.value = 101;
  await tester.pump();
  expect(find.text('101'), findsOneWidget); // сейчас: '100', обновления не приходят
});
```

(Точную сигнатуру конструктора/`of` сверить с `scope_notifier.dart` — примеры использования: `example/scopo_demo/lib/home/demos/c_scope_notifier/`.)

- [ ] **Step 2: фикс** — строка 86: `newWidget.value?.removeListener(...)` → `newWidget.value?.addListener(notifyDependents);`
- [ ] **Step 3:** PASS. Коммит: `fix listener re-subscription on ScopeNotifier.value swap`.

