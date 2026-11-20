#!/usr/bin/env bash
# Revue de code automatisée (M2-03 preuve 1, M1-08, M2-07) : aucune API d'identité
# de l'appareil, aucune persistance, aucun log, aucun `try!` dans les sources de l'app.
# Usage : scripts/check-forbidden-apis.sh [dossier]   (défaut : Proxima/)
# Code de sortie : 0 si rien trouvé, 1 sinon (liste fichier:ligne:motif).
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)/Proxima}"

# Motifs interdits (expressions régulières étendues).
PATTERNS=(
  'UIDevice'
  'identifierForVendor'
  'advertisingIdentifier'
  'hostName'
  'UserDefaults'
  'NSUbiquitousKeyValueStore'
  '(^|[^A-Za-z_.])print\('
  'debugPrint\('
  '(^|[^A-Za-z_.])dump\('
  'NSLog'
  'os_log'
  'Logger\('
  'try!'
)

# Liste blanche explicite : "chemin/relatif/au/dossier.swift:motif" (usage légitime justifié).
# - Services/AppLog.swift : seule façade de journalisation (M3-12), construit les `Logger` par catégorie.
# Seuls les fichiers *.swift du dossier analysé (Proxima/) sont examinés : docs/ n'est pas scanné.
ALLOWLIST=(
  'Services/AppLog.swift:Logger\('
)

found=0
while IFS= read -r -d '' file; do
  rel="${file#"$ROOT"/}"
  for pat in "${PATTERNS[@]}"; do
    allowed=0
    for entry in ${ALLOWLIST[@]+"${ALLOWLIST[@]}"}; do
      [[ "$entry" == "$rel:$pat" ]] && allowed=1
    done
    [[ $allowed -eq 1 ]] && continue
    if matches=$(grep -nE -- "$pat" "$file"); then
      while IFS= read -r m; do
        echo "INTERDIT: $rel:${m%%:*}: motif '$pat'"
      done <<< "$matches"
      found=1
    fi
  done
done < <(find "$ROOT" -name '*.swift' -print0)

if [[ $found -eq 0 ]]; then
  echo "OK : aucune API interdite dans $ROOT"
fi
exit $found
