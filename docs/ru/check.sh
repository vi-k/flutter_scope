#!/bin/sh
# Проверяет русские зеркала публичных документов.
#
# У каждого перевода в шапке записан blob-хеш оригинала, которому он отвечает.
# Хеш разошёлся — оригинал правили, а перевод нет. Нет файла — забыли завести
# зеркало для новой страницы.
#
# Запускать из корня репозитория: sh docs/ru/check.sh
set -eu

cd "$(dirname "$0")/../.."

status=0
checked=0

# 1. У каждого перевода — свежий хеш оригинала.
for translation in docs/ru/README.md docs/ru/doc/*.md \
                   docs/ru/example/*/README.md; do
  [ -e "$translation" ] || continue

  source=$(sed -n 's/^> Перевод `\([^`]*\)`.*/\1/p' "$translation" | head -1)
  recorded=$(sed -n 's/^.*blob `\([0-9a-f]\{40\}\)`.*/\1/p' "$translation" | head -1)

  if [ -z "$source" ] || [ -z "$recorded" ]; then
    echo "НЕТ ШАПКИ: $translation — первой строкой нужен"
    echo '              > Перевод `<оригинал>` (blob `<40 hex>`).'
    status=1
    continue
  fi

  if [ ! -e "$source" ]; then
    echo "НЕТ ОРИГИНАЛА: $translation ссылается на $source"
    status=1
    continue
  fi

  actual=$(git hash-object "$source")
  checked=$((checked + 1))

  if [ "$actual" != "$recorded" ]; then
    echo "УСТАРЕЛ: $translation"
    echo "         оригинал $source сейчас $actual,"
    echo "         в шапке записан         $recorded"
    status=1
  fi
done

# 2. У каждого оригинала — зеркало.
for source in README.md doc/*.md example/*/README.md; do
  translation="docs/ru/$source"
  if [ ! -e "$translation" ]; then
    echo "НЕТ ПЕРЕВОДА: $source (ждали $translation)"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "переводы актуальны: $checked"
fi

exit "$status"
