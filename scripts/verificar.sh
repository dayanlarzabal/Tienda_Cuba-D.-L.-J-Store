#!/usr/bin/env bash
# Comprueba que el paquete está completo y que las variables mínimas existen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▶ Verificando estructura del proyecto…"

need=(
  "proyecto.sh"
  "web.sh"
  ".github/workflows/build-apk.yml"
  ".github/workflows/pages.yml"
  "supabase/01_setup_completo.sql"
  "supabase/supabase_setup.sql"
  "supabase/marketplace_upgrade.sql"
  "README.md"
)

missing=0
for f in "${need[@]}"; do
  if [[ -f "$f" ]]; then
    echo "  ✓ $f"
  else
    echo "  ✗ FALTA: $f"
    missing=1
  fi
done

if [[ $missing -eq 1 ]]; then
  echo "ERROR: faltan archivos."
  exit 1
fi

echo
echo "▶ Comprobando que proyecto.sh y web.sh son ejecutables…"
chmod +x proyecto.sh web.sh scripts/verificar.sh 2>/dev/null || true

echo
echo "✔ Paquete completo y listo."
echo
echo "Siguiente paso:"
echo "  1. Ejecuta supabase/01_setup_completo.sql en Supabase"
echo "  2. Sube esta carpeta a un repositorio GitHub"
echo "  3. Configura SUPABASE_URL y SUPABASE_ANON_KEY como Variables de Actions"
echo "  4. Lanza el workflow «Compilar APK»"
