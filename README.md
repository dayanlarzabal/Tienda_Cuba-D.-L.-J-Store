# HANDMADE D.L.J STORE — Proyecto completo (Marketplace)

**Un solo paquete** con todo vinculado:

- App Android (Flutter) con marketplace multi-vendedor  
- Tienda web (GitHub Pages)  
- Backend completo en Supabase  
- Workflows de GitHub Actions listos  

Cualquier persona puede registrarse, solicitar ser vendedor, publicar productos/APK con sus precios y ganar dinero. Tú ganas una comisión por cada venta. El administrador modera vendedores y publicaciones. Los pagos se verifican manualmente (Transfermóvil CUP/MLC, USDT, TRX, Bitcoin).

---

## Estructura del proyecto

```
DLJ_STORE_FINAL/
├── README.md                          ← este archivo
├── proyecto.sh                        ← genera la app Flutter completa
├── web.sh                             ← genera la tienda web
├── .github/workflows/
│   ├── build-apk.yml                  ← compila el APK
│   └── pages.yml                      ← publica la web en GitHub Pages
└── supabase/
    ├── 01_setup_completo.sql          ← TODO el SQL (recomendado)
    ├── supabase_setup.sql             ← solo la base original
    └── marketplace_upgrade.sql        ← solo la migración marketplace
```

---

## Instalación en 4 pasos

### 1. Supabase

1. Crea un proyecto en [supabase.com](https://supabase.com).
2. Abre **SQL Editor** y ejecuta **todo** el archivo:
   ```
   supabase/01_setup_completo.sql
   ```
   (Si prefieres por partes: primero `supabase_setup.sql` y después `marketplace_upgrade.sql`).
3. Ve a **Authentication → Users** y crea tu usuario administrador.
4. Ejecuta esta línea (cambia el correo):
   ```sql
   insert into public.admins (user_id)
     select id from auth.users where email = 'TU_CORREO@ejemplo.com'
     on conflict do nothing;
   ```
5. Copia de **Project Settings → API**:
   - Project URL → `SUPABASE_URL`
   - anon public key → `SUPABASE_ANON_KEY`

### 2. Repositorio GitHub

1. Crea un repositorio vacío.
2. Sube **todo** el contenido de esta carpeta a la raíz del repo.
3. Ve a **Settings → Secrets and variables → Actions → Variables** y crea:

| Variable             | Valor                                      |
|----------------------|--------------------------------------------|
| `SUPABASE_URL`       | `https://xxxx.supabase.co`                 |
| `SUPABASE_ANON_KEY`  | tu clave anon                              |
| `APP_DOWNLOAD_URL`   | (opcional) URL del APK cuando lo tengas    |

### 3. Compilar el APK

1. **Actions → Compilar APK → Run workflow**.
2. Cuando termine, descarga el artefacto `dlj-store-apk`.
3. Instálalo en Android y prueba con dos cuentas (admin + vendedor).

### 4. Publicar la web

El workflow `pages.yml` se ejecuta al hacer push a `main` (o manualmente).  
La tienda quedará en la URL de GitHub Pages.

---

## Qué puede hacer cada rol

| Rol                    | Funciones |
|------------------------|-----------|
| **Visitante**          | Ver catálogo, comprar, dejar pedidos |
| **Usuario registrado** | Solicitar ser vendedor |
| **Vendedor aprobado**  | Publicar productos (quedan pendientes de moderación), ver sus ventas y comisión |
| **Administrador**      | Aprobar/rechazar vendedores y productos, fijar comisión, verificar pagos, gestionar ajustes de la tienda |

---

## Comisión

- Por defecto: **10 %** (el admin la puede cambiar).
- Se calcula automáticamente en cada línea de pedido.
- Se guarda: lo que le toca al vendedor y lo que le toca a la plataforma.
- El dinero **no se reparte solo**: el admin verifica el pago y coordina el pago al vendedor por fuera.

---

## Limitaciones actuales

1. **Pagos manuales** — El admin verifica cada pedido. No hay payout automático.
2. **APK / archivos digitales** — Se usa URL de descarga externa. Aún no hay Storage privado ni enlaces firmados por compra.
3. **Web** — Tiene la tienda pública completa. El panel de vendedor y el registro de vendedores están en la **app Android**.
4. **Pedidos antiguos** — Los pedidos creados antes de activar el marketplace no tienen atribución de vendedor.

---

## Seguridad

- Usa **solo** la clave `anon` / publishable.
- **Nunca** pongas la `service_role` en la app ni en la web.
- Todas las operaciones sensibles pasan por funciones del servidor que comprueban el usuario o si es admin.

---

## Flujo recomendado de prueba

1. Ejecuta el SQL completo.
2. Compila el APK.
3. Entra con tu cuenta de admin → verifica que ves el panel de administrador.
4. Crea otra cuenta → solicita ser vendedor → apruébala desde el admin.
5. Con la cuenta de vendedor publica un producto → apruébalo desde el admin.
6. Como cliente haz un pedido de prueba y verifica el estado.

---

## Soporte rápido

- Revisa los logs del workflow de GitHub Actions.
- En Supabase → Logs → Postgres / Auth.
- Confirma que ejecutaste el SQL completo y que tu usuario está en `public.admins`.

---

**HANDMADE D.L.J STORE** — Un solo proyecto, marketplace multi-vendedor listo para usar.
