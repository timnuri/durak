#!/usr/bin/env bash
# Скачивает Godot и шаблоны экспорта (если их ещё нет в кэше).
set -euo pipefail
V="${GODOT_VERSION:-4.7.2}"
TPL="$HOME/.local/share/godot/export_templates/${V}.stable"
mkdir -p "$HOME/godot"
if [ ! -x "$HOME/godot/godot" ]; then
  curl -sSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_linux.x86_64.zip"
  unzip -q -o /tmp/godot.zip -d /tmp/godot_unzip
  mv /tmp/godot_unzip/Godot_v${V}-stable_linux.x86_64 "$HOME/godot/godot"
  chmod +x "$HOME/godot/godot"
fi
if [ ! -f "$TPL/version.txt" ]; then
  curl -sSL -o /tmp/tpl.tpz "https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_export_templates.tpz"
  mkdir -p "$TPL"
  # Берём только нужные шаблоны (Android и Web), остальное не распаковываем.
  unzip -q -o /tmp/tpl.tpz "templates/android_*" "templates/web_*" "templates/version.txt" -d /tmp/tpl
  mv /tmp/tpl/templates/* "$TPL/"
  rm -f /tmp/tpl.tpz
fi
"$HOME/godot/godot" --version
