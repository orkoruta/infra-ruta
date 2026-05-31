# Deploy a producción — RUTA

Checklist completo para el go-live. Ejecuta los pasos en orden.
Tiempo estimado: 1–2 horas (sin contar propagación DNS).

---

## Prerequisitos

- Acceso SSH o consola al servidor OCI (149.130.168.24)
- Cuenta en Render con los servicios ya creados (ver `render.yaml`)
- Cuenta Wompi en modo producción con llaves activas
- Dominio `ruta.com` con acceso al panel DNS
- `psql` v18 instalado localmente (o desde el servidor OCI)
- Repositorio `backend-ruta` clonado y con `pnpm install` ejecutado

---

## Paso 1 — Crear la base de datos de producción en OCI

Conéctate al servidor y ejecuta como superusuario PostgreSQL:

```sql
-- Crear base de datos de producción
CREATE DATABASE ruta_prod
  OWNER postgres
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.UTF-8'
  LC_CTYPE 'en_US.UTF-8';

-- Crear usuario de aplicación para producción
CREATE USER ruta_prod_user WITH PASSWORD 'ELIGE_UNA_CONTRASEÑA_SEGURA';

-- Otorgar acceso a la BD
GRANT CONNECT ON DATABASE ruta_prod TO ruta_prod_user;
```

> Usa una contraseña larga y aleatoria (mínimo 32 caracteres). Guárdala en tu gestor de contraseñas.

---

## Paso 2 — Aplicar el esquema

```bash
export PROD_DATABASE_URL="postgresql://ruta_prod_user:PASSWORD@149.130.168.24:26432/ruta_prod"

# Validar primero sin aplicar
DRY_RUN=1 bash scripts/migrate_prod.sh

# Aplicar el esquema completo
bash scripts/migrate_prod.sh
```

El script aplica `docs-ruta/bd/ruta_postgres.sql` que incluye:
- Todos los roles de BD (`ruta_app`, `ruta_jobs`, `ruta_readonly`)
- Todas las tablas (Sprints 0–6), particionadas por `client_id`
- RLS, triggers, funciones, índices
- Cliente plataforma (`id = 0`)
- Catálogo de estados (state_catalog)
- Parámetros globales por defecto (client_id = 0)

---

## Paso 3 — Verificar la migración

```bash
bash scripts/verify_prod.sh
```

Todos los checks deben mostrar `✓` antes de continuar.

---

## Paso 4 — Crear el primer ADMIN_RUTA

```bash
bash scripts/create_admin_ruta_prod.sh
```

Ingresa email y contraseña cuando el script lo solicite.
Guarda las credenciales en el gestor de contraseñas del equipo.

---

## Paso 5 — Configurar variables de entorno en Render

En el dashboard de Render, para el servicio `ruta-api` (y `ruta-api-worker`), configura:

| Variable | Valor |
|---|---|
| `DATABASE_URL` | `postgresql://ruta_prod_user:PASSWORD@149.130.168.24:26432/ruta_prod` |
| `JWT_SECRET` | Cadena aleatoria de 64+ caracteres |
| `WOMPI_PUBLIC_KEY` | Llave pública de producción Wompi |
| `WOMPI_PRIVATE_KEY` | Llave privada de producción Wompi |
| `WOMPI_WEBHOOK_SECRET` | Events secret de producción Wompi |
| `LOGTAIL_TOKEN` | Token de fuente en Better Stack (opcional) |
| `NODE_ENV` | `production` |
| `NPM_TOKEN` | PAT con `read:packages` para `@orkoruta/*` |

Para `ruta-admin` y `ruta-storefront`:

| Variable | Valor |
|---|---|
| `NEXT_PUBLIC_API_URL` | `https://api.ruta.com/v1` |
| `NPM_TOKEN` | PAT con `read:packages` |

---

## Paso 6 — Configurar Wompi para producción

1. Entra a tu cuenta en [wompi.com](https://wompi.com) → **Mis negocios** → selecciona el negocio.
2. Cambia a modo **Producción**.
3. Copia las tres llaves y pégalas en Render (Paso 5).
4. En Wompi, configura la URL de webhook:
   ```
   https://api.ruta.com/webhooks/wompi
   ```
5. Activa los eventos: `transaction.updated`.

---

## Paso 7 — Disparar redeploy en Render

Una vez configuradas las env vars, Render redesplegará automáticamente.
Si no, ve al servicio y haz clic en **Manual Deploy → Deploy latest commit**.

Verifica que el healthcheck responde:
```bash
curl https://api.ruta.com/healthz
# Esperado: {"status":"ok"}
```

---

## Paso 8 — Configurar DNS

En tu proveedor de DNS, agrega tres registros CNAME:

| Nombre | Tipo | Valor |
|---|---|---|
| `api` | CNAME | `ruta-api.onrender.com` |
| `app` | CNAME | `ruta-admin.onrender.com` |
| `tienda` | CNAME | `ruta-storefront.onrender.com` |

Render detecta los dominios automáticamente y emite certificados TLS via Let's Encrypt.
La propagación DNS puede tardar hasta 48 horas (normalmente menos de 1 hora).

En Render, ve a cada servicio → **Settings → Custom Domains** → agrega el dominio.

---

## Paso 9 — Smoke test

Una vez propagado el DNS, verifica:

```bash
# API
curl https://api.ruta.com/healthz

# Admin (debe redirigir al login)
curl -I https://app.ruta.com

# Storefront (debe mostrar 404 elegante sin tenant)
curl -I https://tienda.ruta.com
```

Luego entra a `https://app.ruta.com` con las credenciales del ADMIN_RUTA y verifica:
- [ ] Login funciona
- [ ] Dashboard carga
- [ ] Vista de Control responde

---

## Paso 10 — Onboarding del cliente piloto (6.QA-3)

Con producción estable:

1. Entra como ADMIN_RUTA a `https://app.ruta.com`.
2. Crea el primer Cliente en **Clientes → Nuevo cliente**.
3. Impersona al nuevo ADMIN_CLIENT desde Vista de Control.
4. Configura junto al cliente:
   - Catálogo (categorías y productos)
   - Repartidores
   - Puntos de retiro (si aplica)
   - Wompi del cliente (sus propias llaves)
5. Realiza el primer pedido de prueba.
6. Verifica que el flujo completo funciona: checkout → pago → asignación → entrega.

---

## Rollback

Si algo falla y necesitas revertir:

```bash
# Eliminar el schema de producción (DESTRUCTIVO — solo si la BD de prod tiene pocos o ningún dato real)
psql "$PROD_DATABASE_URL" -c "DROP SCHEMA ruta CASCADE;"

# Volver a aplicar desde cero
bash scripts/migrate_prod.sh
```

Si ya hay datos reales, **no hagas rollback** — contacta al equipo para evaluar una migración incremental.
