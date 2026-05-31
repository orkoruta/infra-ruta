# Backup y Restore de BD — RUTA

Procedimiento para hacer backup y restore del schema `ruta` en PostgreSQL (OCI, host `149.130.168.24`, puerto `26432`).

Los backups se generan como archivos `.sql.gz` (SQL plano comprimido con gzip), lo que permite inspeccionarlos, transportarlos y restaurarlos sin herramientas especiales más allá de `gunzip` y `psql`.

> **Requisito de versión:** `pg_dump` debe ser de la misma versión mayor que el servidor PostgreSQL (o superior). El script verifica esto automáticamente. Si hay incompatibilidad, instalá la versión correcta de `postgresql-client`:
> ```bash
> # En Ubuntu/Debian, agregar el repo oficial de PostgreSQL y luego:
> sudo apt install postgresql-client-18
> ```
> Referencia: https://www.postgresql.org/download/linux/ubuntu/

---

## Variables de entorno

Todos los scripts leen la configuración exclusivamente de variables de entorno. **No hardcodear credenciales.**

| Variable           | Descripción                              | Requerida | Ejemplo                |
|--------------------|------------------------------------------|-----------|------------------------|
| `DB_HOST`          | Host del servidor PostgreSQL             | Sí        | `149.130.168.24`       |
| `DB_PORT`          | Puerto del servidor PostgreSQL           | Sí        | `26432`                |
| `DB_NAME`          | Nombre de la base de datos               | Sí        | `rutadb`               |
| `DB_USER`          | Usuario de la base de datos              | Sí        | `rutauser`             |
| `DB_PASSWORD`      | Password del usuario de BD               | Sí        | `s3cr3t0`              |
| `BACKUP_DIR`       | Directorio local de salida del backup    | No        | `./backups` (default)  |
| `BACKUP_KEEP_DAYS` | Días de retención de backups locales     | No        | `7` (default)          |

### Configuración para desarrollo

Las credenciales de dev están en `backend-ruta/.env`. Exportar antes de ejecutar los scripts:

```bash
export DB_HOST=149.130.168.24
export DB_PORT=26432
export DB_NAME=rutadb
export DB_USER=rutauser
export DB_PASSWORD=<password_del_.env>
```

### Configuración para producción (Render)

Las variables de entorno de producción se configuran en el dashboard de Render:

1. Ir a [dashboard.render.com](https://dashboard.render.com).
2. Seleccionar el servicio o el cron job de backup.
3. Navegar a **Environment**.
4. Agregar cada variable (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`).
5. Hacer clic en **Save Changes**.

---

## Ejecutar backup manual

```bash
DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser \
DB_PASSWORD=<password> bash scripts/backup_db.sh
```

Con directorio de salida y retención personalizados:

```bash
DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser \
DB_PASSWORD=<password> \
BACKUP_DIR=/var/backups/ruta \
BACKUP_KEEP_DAYS=30 \
bash scripts/backup_db.sh
```

**Salida esperada:**

```
[INFO]  === Backup BD RUTA ===
[INFO]  Inicio   : 2026-05-30 03:00:01
[INFO]  Host     : 149.130.168.24:26432
[INFO]  BD       : rutadb  (schema: ruta)
[INFO]  Archivo  : ./backups/ruta_backup_20260530_030001.sql.gz
[INFO]  Retención: 7 días

[INFO]  Ejecutando pg_dump | gzip ...
[OK]    Backup completado exitosamente.
[INFO]  Archivo : ./backups/ruta_backup_20260530_030001.sql.gz
[INFO]  Tamaño  : 1.2M

[INFO]  Aplicando política de retención (7 días) en ./backups ...
[INFO]  Sin backups expirados para eliminar.

[OK]    Proceso finalizado: 2026-05-30 03:00:04
```

---

## Backup automático

### Opción 1: Cron Job en Render

1. Ir a [dashboard.render.com](https://dashboard.render.com) > **New** > **Cron Job**.
2. Configurar:
   - **Name:** `ruta-backup-db`
   - **Schedule:** `0 3 * * *` (3:00 AM UTC diario)
   - **Command:** `bash scripts/backup_db.sh`
3. Agregar las variables de entorno (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`).
4. Opcionalmente, agregar `BACKUP_DIR` y `BACKUP_KEEP_DAYS`.

### Opción 2: Cron del sistema operativo

En el servidor o VM donde están los scripts, editar el crontab con `crontab -e`:

```cron
# Backup diario a las 3:00 AM
0 3 * * * DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser DB_PASSWORD=<password> BACKUP_DIR=/var/backups/ruta bash /ruta/infra-ruta/scripts/backup_db.sh >> /var/log/ruta_backup.log 2>&1
```

> **Nota de seguridad:** Evitar poner la password directamente en el crontab si el archivo tiene permisos amplios. Preferir cargar desde un archivo de entorno con permisos `600`:
>
> ```cron
> 0 3 * * * set -a; . /etc/ruta/backup.env; set +a; bash /ruta/infra-ruta/scripts/backup_db.sh >> /var/log/ruta_backup.log 2>&1
> ```

---

## Verificar un backup

Antes de restaurar, verificar que el archivo `.sql.gz` está íntegro:

```bash
# 1. Verificar que gzip puede descomprimir el archivo sin errores
gunzip -t backups/ruta_backup_20260530_030001.sql.gz && echo "OK: archivo integro"

# 2. Inspeccionar el contenido (primeras líneas del SQL)
gunzip -c backups/ruta_backup_20260530_030001.sql.gz | head -30

# 3. Contar objetos en el dump (tablas, índices, etc.)
gunzip -c backups/ruta_backup_20260530_030001.sql.gz | grep -c '^CREATE TABLE'
```

Para verificar la conectividad con la BD destino antes de restaurar:

```bash
DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser \
PGPASSWORD=<password> psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();"
```

---

## Ejecutar restore

> **Advertencia:** El restore sobreescribe los datos actuales del schema `ruta`. Esta operación **no se puede deshacer**. Toma un backup fresco antes de restaurar si hay datos en producción que quieras conservar.

```bash
DB_HOST=149.130.168.24 DB_PORT=26432 DB_NAME=rutadb DB_USER=rutauser \
DB_PASSWORD=<password> \
bash scripts/restore_db.sh backups/ruta_backup_20260530_030001.sql.gz
```

El script pedirá confirmación explícita (escribir `si`) antes de proceder.

Para omitir la confirmación (útil en CI/CD o scripts automatizados):

```bash
DB_HOST=... DB_PASSWORD=<password> \
bash scripts/restore_db.sh backups/ruta_backup_20260530_030001.sql.gz --yes
```

**Salida esperada tras restore exitoso:**

```
[INFO]  === Restaurando backup ===
[INFO]  Inicio : 2026-05-30 10:00:01

[INFO]  Ejecutando gunzip | psql ...

[INFO]  Restore SQL completado. Ejecutando verificación post-restore...

─────────────────────────────────────────────
Conteo de filas en tablas clave (schema ruta):
─────────────────────────────────────────────

  Tabla                Filas
  -------------------- -----
  clients              3
  users                18
  orders               145

[OK]    Restore completado exitosamente: 2026-05-30 10:00:08
```

---

## Restore de emergencia (paso a paso)

1. **Identificar el backup** a restaurar (el más reciente o el requerido):
   ```bash
   ls -lht /var/backups/ruta/ | head -10
   ```

2. **Verificar integridad** del archivo:
   ```bash
   gunzip -t /var/backups/ruta/ruta_backup_20260530_030001.sql.gz && echo "OK"
   ```

3. **Notificar al equipo** antes de ejecutar el restore (canal de incidentes).

4. **Tomar un backup del estado actual** (si la BD aún está accesible):
   ```bash
   DB_HOST=... DB_PASSWORD=<password> bash scripts/backup_db.sh
   ```

5. **Ejecutar el restore**:
   ```bash
   DB_HOST=... DB_PASSWORD=<password> \
   bash scripts/restore_db.sh /var/backups/ruta/ruta_backup_20260530_030001.sql.gz
   ```

6. **Verificar la aplicación** con una prueba de humo:
   ```bash
   curl -f http://localhost:3001/health
   ```

7. **Documentar el incidente**: fecha, causa, backup usado, tiempo de restauración.

---

## Política de retención recomendada

| Tipo     | Frecuencia | Retención         |
|----------|------------|-------------------|
| Diario   | 3:00 AM    | 7 días (default)  |
| Semanal  | Domingo    | 4 semanas         |
| Pre-migración | Manual | Conservar indefinidamente |

Para retención semanal de 4 semanas, usar `BACKUP_KEEP_DAYS=28`.
