#!/bin/bash
# Downloads the on-device language model that is bundled into the iOS app.
# The weights (~650 MB) are not kept in git; run this once before building for a device.
set -euo pipefail

REPO="mlx-community/Qwen3.5-0.8B-MLX-4bit"
REVISION="${MODEL_REVISION:-main}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/ios/Models/TaskModel"

mkdir -p "$DEST"
FILES=$(curl -fsSL "https://huggingface.co/api/models/$REPO/tree/$REVISION" | python3 -c 'import sys, json; print("\n".join(f["path"] for f in json.load(sys.stdin) if f["type"] == "file" and f["path"] not in ("README.md", ".gitattributes")))')
for FILE in $FILES; do
  if [ -s "$DEST/$FILE" ]; then echo "have $FILE"; continue; fi
  echo "downloading $FILE"
  curl -fL --retry 3 -o "$DEST/$FILE.part" "https://huggingface.co/$REPO/resolve/$REVISION/$FILE"
  mv "$DEST/$FILE.part" "$DEST/$FILE"
done
echo "$REPO@$REVISION" > "$DEST/SOURCE.txt"
du -sh "$DEST"
