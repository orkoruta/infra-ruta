# Configuración de Observabilidad — RUTA

Guía para activar y usar el sistema de logs centralizado en producción con Logtail (Better Stack).

---

## 1. Obtener un token de Logtail

1. Ir a [https://logtail.com](https://logtail.com) e iniciar sesión (o crear cuenta).
2. En el panel lateral, ir a **Sources**.
3. Hacer clic en **New Source**.
4. Seleccionar plataforma: **Node.js**.
5. Nombrar el source (ej. `ruta-backend-production`).
6. Copiar el **Source Token** que aparece en la pantalla de configuración.

---

## 2. Configurar la variable de entorno `LOGTAIL_TOKEN` en Render

1. Ir al [Dashboard de Render](https://dashboard.render.com).
2. Seleccionar el servicio `ruta-api` (o el nombre configurado en `render.yaml`).
3. Navegar a **Environment** en el menú lateral.
4. Hacer clic en **Add Environment Variable**.
5. Agregar:
   - **Key:** `LOGTAIL_TOKEN`
   - **Value:** (pegar el token copiado de Logtail)
6. Hacer clic en **Save Changes**.
7. Render reiniciará el servicio automáticamente con la nueva variable.

> El transporte Logtail solo se activa cuando `NODE_ENV=production` Y `LOGTAIL_TOKEN` está definido.
> En desarrollo, los logs siguen usando `pino-pretty` localmente.

---

## 3. Queries útiles en Logtail

Una vez que los logs llegan, usar el buscador de Logtail con los siguientes filtros:

### Filtrar por cliente (tenant)

```
client_id: 42
```

Ver todos los logs de un cliente específico (tenant aislamiento).

### Ver errores de un request específico

```
trace_id: "550e8400-e29b-41d4-a716-446655440000"
```

Trazar todos los eventos de un request usando su UUID único.

### Errores 5xx en los últimos 30 minutos

```
status: [500 TO 599]
```

### Actividad de un usuario específico

```
user_id: 123 AND user_type: "ADMIN_CLIENT"
```

### Latencia alta (requests lentos)

```
durationMs: [2000 TO *]
```

### Errores de autenticación

```
status: 401 OR status: 403
```

---

## 4. Umbrales de alerta recomendados

Configurar en Logtail > **Alerts** los siguientes umbrales:

| Métrica | Condición | Acción sugerida |
|---|---|---|
| Tasa de errores 5xx | > 1% de requests en ventana de 5 min | Notificación Slack + email |
| Latencia p95 | > 2 segundos sostenida por 5 min | Notificación Slack |
| Errores de autenticación en ráfaga | > 50 en 1 minuto desde misma IP | Alerta de seguridad |
| Logs con `status: 500` | Cualquier ocurrencia | Notificación inmediata |

Para crear una alerta en Logtail:

1. Ir a **Alerts** en el panel lateral.
2. Hacer clic en **New Alert**.
3. Configurar la query, el umbral y el canal de notificación (email, Slack webhook, PagerDuty).

---

## 5. Verificar que los logs llegan en producción

Después de deployar con `LOGTAIL_TOKEN` configurado:

1. Ir a Logtail > Sources > seleccionar el source configurado.
2. Hacer clic en **Live Tail** para ver logs en tiempo real.
3. Hacer un request a un endpoint de salud (ej. `GET /health`).
4. Confirmar que aparece una entrada con los campos:
   - `trace_id` — UUID único por request
   - `client_id` — null para rutas públicas, número para rutas autenticadas
   - `user_id` — null para rutas públicas, número para rutas autenticadas
   - `user_type` — null para rutas públicas, rol del usuario para rutas autenticadas
   - `method`, `url`, `status`, `durationMs`

Si no aparecen logs en 1-2 minutos:

- Verificar que `NODE_ENV=production` está configurado en Render.
- Verificar que `LOGTAIL_TOKEN` no tiene espacios ni caracteres extra.
- Revisar los logs del proceso en Render > Logs para ver errores de inicialización.

---

## 6. Campos de log disponibles por request

Cada log de request HTTP incluye:

| Campo | Descripción |
|---|---|
| `trace_id` | UUID v4 único generado por request |
| `requestId` | ID de request (del header `X-Request-Id` o generado) |
| `method` | Método HTTP (GET, POST, etc.) |
| `url` | URL completa del request |
| `status` | Código de respuesta HTTP |
| `durationMs` | Tiempo de respuesta en milisegundos |
| `userAgent` | User-Agent del cliente |
| `client_id` | ID del tenant (null si no autenticado) |
| `user_id` | ID del usuario (null si no autenticado) |
| `user_type` | Rol del usuario (null si no autenticado) |
