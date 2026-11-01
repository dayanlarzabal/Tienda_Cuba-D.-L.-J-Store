# HANDMADE D.L.J STORE — APK

## Cómo subir a GitHub (importante)

Debes conservar la carpeta **android/**.

### Opción A (recomendada en PC)
```bash
git clone https://github.com/dayanlarzabal/D.-L.-J-Store.git
cd D.-L.-J-Store
# Copia dentro del repo la carpeta android/ y .github/ de este zip
git add android .github
git commit -m "Fix: proyecto Flutter android completo"
git push
```

### Opción B (móvil)
1. Borra en el repo archivos sueltos de Flutter que estén en la raíz (pubspec, MainActivity, etc.) si confunden.
2. Sube la carpeta **android** completa (con lib, assets, android interno, pubspec.yaml).
3. Sube **.github/workflows/build-apk.yml**.

### Compilar
Actions → Build Android APK → Run workflow → descarga dlj-store-apk.

### Estructura correcta
```
D.-L.-J-Store/
  .github/workflows/build-apk.yml
  android/
    pubspec.yaml
    lib/
      main.dart
      screens/
      ...
    assets/images/logo.png
    android/          # plataforma Android (generada por Flutter)
```
