#!/usr/bin/env bash
# Скачивает ванильный сервер Minecraft с серверов Mojang и ставит его в ./server.
#
#   ./update-server.sh            # последний релиз
#   ./update-server.sh 1.20.4     # конкретная версия
#
# Скрипт проверяет SHA1 скачанного файла, сохраняет копию в server/versions/<версия>/
# и только потом подменяет server/server.jar.

set -euo pipefail

MANIFEST="https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/server"
WANTED="${1:-}"

command -v curl    >/dev/null || { echo "нужен curl";    exit 1; }
command -v python3 >/dev/null || { echo "нужен python3"; exit 1; }

# sha1sum есть в Linux (coreutils), shasum — в macOS
if command -v sha1sum >/dev/null; then
  sha1_of() { sha1sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null; then
  sha1_of() { shasum -a 1 "$1" | awk '{print $1}'; }
else
  echo "нужен sha1sum или shasum" >&2
  exit 1
fi

echo "==> Читаю манифест версий Mojang"
read -r VERSION URL SHA1 < <(
  curl -fsSL "$MANIFEST" | python3 -c '
import json, sys, urllib.request
manifest = json.load(sys.stdin)
wanted = sys.argv[1] or manifest["latest"]["release"]
entry = next((v for v in manifest["versions"] if v["id"] == wanted), None)
if entry is None:
    sys.exit(f"версия {wanted} не найдена в манифесте")
meta = json.load(urllib.request.urlopen(entry["url"]))
server = meta["downloads"]["server"]
print(meta["id"], server["url"], server["sha1"])
' "$WANTED"
)

echo "==> Версия: $VERSION"

CURRENT=""
[[ -f "$SERVER_DIR/.version" ]] && CURRENT="$(cat "$SERVER_DIR/.version")"
if [[ "$CURRENT" == "$VERSION" && -f "$SERVER_DIR/server.jar" ]]; then
  echo "==> Уже установлена $VERSION, ничего делать не нужно"
  exit 0
fi

DEST_DIR="$SERVER_DIR/versions/$VERSION"
DEST="$DEST_DIR/server-$VERSION.jar"
mkdir -p "$DEST_DIR"

if [[ ! -f "$DEST" ]]; then
  echo "==> Скачиваю $URL"
  curl -fL --progress-bar -o "$DEST.tmp" "$URL"
  mv "$DEST.tmp" "$DEST"
fi

echo "==> Проверяю SHA1"
ACTUAL="$(sha1_of "$DEST")"
if [[ "$ACTUAL" != "$SHA1" ]]; then
  rm -f "$DEST"
  echo "SHA1 не совпал: ожидался $SHA1, получен $ACTUAL" >&2
  exit 1
fi

cp "$DEST" "$SERVER_DIR/server.jar"
echo "$VERSION" > "$SERVER_DIR/.version"

echo "==> Готово: server/server.jar -> $VERSION"
echo "    Не забудьте сделать бэкап мира перед первым запуском на новой версии:"
echo "      tar czf world-backup-\$(date +%F).tar.gz server/1488"
