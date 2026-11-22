#!/bin/bash
# Конвертирует звук сирены в формат, который понимает iOS.
# Нужен только для локальной сборки на macOS (в GitHub Actions это делается автоматически).
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)/AlertOrenburg/Sources/Resources/Sounds"
mkdir -p "$DIR"

found=0
for f in "$DIR"/*.mp3; do
  [ -e "$f" ] || continue
  found=1
  base="${f%.mp3}"
  if afconvert -f caff -d LEI16@44100 -c 1 "$f" "$base.caf"; then
    echo "OK: $base.caf"
  elif afconvert -f AIFF -d BEI16@44100 -c 1 "$f" "$base.aiff"; then
    echo "OK: $base.aiff"
  else
    echo "Не удалось конвертировать $f" >&2
    exit 1
  fi
done

if [ "$found" = "0" ]; then
  echo "Нет mp3 в $DIR — нечего конвертировать"
fi
