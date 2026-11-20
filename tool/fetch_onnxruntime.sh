#!/usr/bin/env bash
# Pré-installe ONNX Runtime pour le build desktop Linux / Windows de la CI.
#
# Pourquoi : le CMake de `flutter_onnxruntime` télécharge ONNX Runtime depuis
# github.com/microsoft/onnxruntime/releases à chaque configuration. Ce dépôt
# renvoie 404 depuis le 2026-11-17 (v0.5.0 et v0.6.0 n'ont donc aucun binaire de
# bureau). Le plugin saute son téléchargement quand le dossier d'extraction
# existe déjà avec `include/onnxruntime_cxx_api.h` : on le remplit ici depuis le
# paquet NuGet officiel Microsoft.ML.OnnxRuntime (en-têtes + bibliothèques natives).
#
# À lancer à la racine du dépôt, après `flutter pub get` et avant `flutter build`.
#   usage : tool/fetch_onnxruntime.sh linux|windows
#
# À retirer quand le plugin sait récupérer ONNX Runtime ailleurs que sur GitHub.
set -euo pipefail

os="${1:?usage: $0 linux|windows}"

# Version que le plugin attend (nom du dossier d'extraction, `ONNXRUNTIME_VERSION`
# dans flutter_onnxruntime/<os>/CMakeLists.txt) : à tenir alignée si le plugin change.
plugin_version="1.28.3"
# Version réellement installée. NuGet n'a pas 1.28.3 ; 1.28.0 est la plus proche
# (même API : le plugin appelle OrtGetApi avec la version de ses en-têtes).
nuget_version="1.28.0"
nupkg_sha256="769d1d3ea8ab6cd69f737c9dd4d4462aa4ad0ccfa106eaf506efc40d7bead5db"
nupkg_url="https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${nuget_version}/microsoft.ml.onnxruntime.${nuget_version}.nupkg"

case "$os" in
  linux)
    plugin_build="build/linux/x64/release/plugins/flutter_onnxruntime"
    target="$plugin_build/onnxruntime/onnxruntime-linux-x64-${plugin_version}"
    native="runtimes/linux-x64/native"
    ;;
  windows)
    plugin_build="build/windows/x64/plugins/flutter_onnxruntime"
    target="$plugin_build/onnxruntime/onnxruntime-win-x64-${plugin_version}"
    native="runtimes/win-x64/native"
    ;;
  *)
    echo "OS inconnu : $os (attendu : linux ou windows)" >&2
    exit 2
    ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Téléchargement de Microsoft.ML.OnnxRuntime ${nuget_version}…"
curl --fail --silent --show-error --location --retry 3 \
  --output "$work/ort.nupkg" "$nupkg_url"

actual="$(sha256sum "$work/ort.nupkg" | cut -d' ' -f1)"
if [ "$actual" != "$nupkg_sha256" ]; then
  echo "SHA-256 inattendu pour le paquet NuGet : $actual (attendu $nupkg_sha256)" >&2
  exit 1
fi

# `cmake -E tar` lit les .zip sur les deux OS (pas d'`unzip` sous Git Bash).
(cd "$work" && cmake -E tar xf ort.nupkg -- "$native" build/native/include)

rm -rf "$target"
mkdir -p "$target/include" "$target/lib"
cp "$work"/build/native/include/*.h "$target/include/"

if [ "$os" = linux ]; then
  # Même disposition que le tarball officiel : le fichier réel, puis les liens
  # `.so.1` (SONAME de la bibliothèque) et `.so` (celui que cherche le plugin).
  cp "$work/$native/libonnxruntime.so" "$target/lib/libonnxruntime.so.${nuget_version}"
  ln -s "libonnxruntime.so.${nuget_version}" "$target/lib/libonnxruntime.so.1"
  ln -s "libonnxruntime.so.1" "$target/lib/libonnxruntime.so"
else
  cp "$work/$native/onnxruntime.lib" "$work/$native/onnxruntime.dll" "$target/lib/"
fi

echo "ONNX Runtime ${nuget_version} installé dans $target"
