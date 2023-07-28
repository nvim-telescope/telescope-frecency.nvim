#!/bin/bash
NVIM=${NVIM:-nvim}
while IFS= read -r -d '' file; do
  TMP=$(mktemp)
  $NVIM --headless --clean -u lua/frecency/tests/lint.lua "$file" "$TMP"
  size=$(wc -c "$TMP" | awk '{print $1}')
  if ((size > 0)); then
    ERR=1
    cat "$TMP"
  fi
done < <(find . -type f -name '*.lua' -print0)
if [[ $ERR = 1 ]]; then
  exit 1
fi
