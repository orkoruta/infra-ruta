# Crear una landing custom para un Cliente Full

Guía paso a paso para crear y desplegar una landing con branding propio
para un Cliente Full de RUTA (modalidad `CUSTOM_LANDING_BY_RUTA`).

---

## Prerrequisitos

- El cliente ya existe en la BD de RUTA con `client_type = 'FULL'`.
- Tienes los assets de branding del cliente: logo, paleta de colores, tipografías.
- `GITHUB_TOKEN` disponible en el entorno con permisos `repo` + `workflow`.
- `jq` y `curl` instalados (`sudo apt install jq curl`).
- La plataforma RUTA está desplegada en producción (backend + admin accesibles).

---

## Paso 1 — Crear el repo desde el template

```bash
# Desde la raíz del workspace local (donde vive infra-ruta/)
export GITHUB_TOKEN=<tu-PAT>
bash infra-ruta/scripts/create_landing.sh <slug-del-cliente>
```

El script:
1. Crea el repo `landing-<slug>` en la org `orkoruta` en GitHub.
2. Clona el template (`landing-template`) como base.
3. Deja el repo en `frontend-clients-ruta/<slug>/`.

Verifica que el repo se creó y tiene la estructura correcta:

```bash
ls frontend-clients-ruta/<slug>/src/app/
# Debe mostrar: (auth)/ cart/ checkout/ orders/ page.tsx recurrence/ product/
```

---

## Paso 2 — Configurar variables de entorno

Copia el archivo de ejemplo y edítalo:

```bash
cd frontend-clients-ruta/<slug>
cp .env.example .env.local
```

Edita `.env.local`:

```env
NEXT_PUBLIC_API_URL=https://api.ruta.com.co      # URL del backend de producción
NEXT_PUBLIC_CLIENT_SLUG=<slug-del-cliente>         # slug único del cliente en RUTA
```

---

## Paso 3 — Aplicar el branding del cliente

Las landings NO usan `@orkoruta/ui`. Cada landing tiene su propio sistema de diseño.

### 3.1 Colores y tipografías

Edita `tailwind.config.ts` para definir los colores del cliente:

```typescript
// tailwind.config.ts
theme: {
  extend: {
    colors: {
      brand: {
        primary: '#...',    // color principal del cliente
        secondary: '#...',
        accent: '#...',
      }
    },
    fontFamily: {
      sans: ['<Fuente del cliente>', 'sans-serif'],
    }
  }
}
```

### 3.2 Logo y assets

Coloca el logo y demás assets en `public/`:

```
public/
├── logo.png        (o .svg)
├── favicon.ico
└── images/
    └── hero.jpg    (imagen principal de la home)
```

### 3.3 Layout y navegación

Edita `src/app/layout.tsx` para incluir el header y footer del cliente.
Usa los colores `brand.*` definidos en Tailwind.

---

## Paso 4 — Conectar páginas con la API de RUTA

Cada página placeholder debe conectarse con los endpoints de la API.
El helper `src/lib/api_client.ts` ya está configurado.

### Páginas a implementar (por orden de prioridad)

| Página | Endpoint principal | Notas |
|---|---|---|
| `src/app/page.tsx` | `GET /buyer/products` | Home con catálogo |
| `src/app/product/[id]/page.tsx` | `GET /buyer/products/:id` | Detalle de producto |
| `src/app/cart/page.tsx` | (state local) | Carrito en memoria |
| `src/app/(auth)/login/page.tsx` | `POST /auth/login` | Login comprador |
| `src/app/(auth)/register/page.tsx` | `POST /auth/register` | Registro comprador |
| `src/app/checkout/page.tsx` | `POST /buyer/orders` | Crear pedido |
| `src/app/orders/page.tsx` | `GET /buyer/orders` | Mis pedidos |
| `src/app/orders/[id]/page.tsx` | `GET /buyer/orders/:id` | Detalle pedido |
| `src/app/recurrence/page.tsx` | `GET /buyer/recurrence` | Pedidos recurrentes |

### Ejemplo de llamada autenticada

```typescript
import { apiClient } from '@/lib/api_client'

// Listar productos del catálogo del cliente
const products = await apiClient.get<Product[]>('/buyer/products?page=1&page_size=20')
```

---

## Paso 5 — Probar en local

```bash
cd frontend-clients-ruta/<slug>
pnpm install
pnpm dev
```

Valida el flujo completo:
1. El comprador se registra / inicia sesión.
2. Navega al catálogo y agrega un producto al carrito.
3. Completa el checkout (dirección, método de pago).
4. El pedido queda en DRAFT / PENDING_CONFIRM en el panel admin.
5. El admin confirma y el estado avanza.
6. La landing muestra el estado actualizado en «Mis pedidos».

---

## Paso 6 — Verificar antes del deploy

```bash
pnpm typecheck   # EXIT 0
pnpm build       # EXIT 0
```

Si alguno falla, corregir antes de continuar.

---

## Paso 7 — Deploy en Render (solo en el deploy final de Fase 3)

El deploy se realiza **una sola vez** al finalizar todos los bloques de Fase 3
y aprobar la Validación Pre-Deploy Final.

```bash
# En la Validación Pre-Deploy Final se abre el PR del repo landing-<slug>
# y se mergea en orden: shared → backend → frontend → landing

# Configurar en Render:
# - Repo: orkoruta/landing-<slug>
# - Build command: pnpm install && pnpm build
# - Start command: pnpm start
# - Env vars: NEXT_PUBLIC_API_URL, NEXT_PUBLIC_CLIENT_SLUG

# Configurar DNS del cliente:
# CNAME landing.<dominio-del-cliente>.com → <servicio>.onrender.com
```

---

## Restricciones de diseño

| Permitido | Prohibido |
|---|---|
| Componentes propios del repo | `import '@orkoruta/ui'` |
| `@orkoruta/shared` (tipos/validators) | Exponer marca RUTA visualmente |
| Tailwind con branding del cliente | Hardcodear `client_id` en código |
| Assets en `public/` del repo | Tokens en `localStorage` |

---

## Problemas comunes

**El build falla con error de tipos:**
Verifica que `@orkoruta/shared` esté correctamente instalado:
```bash
pnpm install && pnpm typecheck
```

**Las llamadas a la API dan 401:**
Asegúrate de que el comprador inició sesión correctamente y la cookie
`access_token` está presente (las llamadas usan `credentials: 'include'`).

**La landing muestra datos de otro cliente:**
Verifica que `NEXT_PUBLIC_CLIENT_SLUG` corresponde al slug correcto del
cliente en la BD. Todos los endpoints del comprador filtran por `client_id`
derivado del JWT.
