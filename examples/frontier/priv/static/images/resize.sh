#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if ! command -v magick >/dev/null 2>&1; then
  echo 'ImageMagick is required. On macOS: brew install imagemagick' >&2
  exit 1
fi

force=false
case "${1:-}" in
  '') ;;
  --force) force=true ;;
  *) echo "Usage: $0 [--force]" >&2; exit 1 ;;
esac

temporary=''
trap 'if [[ -n "$temporary" ]]; then rm -f -- "$temporary"; fi' EXIT

while IFS= read -r -d '' source; do
  group=$(dirname -- "$(dirname -- "$source")")
  name=$(basename -- "$source")
  for size in 512 256; do
    target="$group/$size/$name"
    if $force || [[ ! -f "$target" || "$source" -nt "$target" || "${BASH_SOURCE[0]}" -nt "$target" ]]; then
      mkdir -p -- "$group/$size"
      temporary=$(mktemp "$group/$size/.resize.XXXXXX")
      magick "$source" -filter Lanczos -resize "${size}x${size}" \
        -background none -gravity center -extent "${size}x${size}" \
        -define png:color-type=6 "PNG:$temporary"
      mv -f -- "$temporary" "$target"
      temporary=''
      echo "Updated $target"
    fi
  done
done < <(find . -type f -path '*/originals/*' -iname '*.png' -print0)
