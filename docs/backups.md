# Backups y Restore de BD — RUTA

Procedimiento para hacer backup y restore del schema `ruta` en PostgreSQL.

---

## Variables de entorno requeridas

| Variable        | Descripción                              | Ejemplo                   |
|-----------------|------------------------------------------|---------------------------|
| `PGPASSWORD`    | Password del usuario de BD **(requerido)** | `s3cr3t0`               |
| `DB_HOST`       | Host del servidor PostgreSQL             | `149.130.168.24`          |
| `DB_PORT`       | Puerto del servidor PostgreSQL           | `26432`                   |
| `DB_NAME`       | Nombre de la base de datos               | `rutadb`                  |
| `DB_USER`       | Usuario de la base de datos              | `ruta`                    |
| `BACKUP_DIR`    | Directorio local de salida del backup    | `/var/backups/ruta`       |
| `BACKUP_BUCKET` | Nombre del bucket S3 o OCI (opcional)    | `ruta-backups-prod`       |

Los valores con default no necesitan definirse si coinciden con la configuración estándar de producción.

---

## Ejecutar backup

```bash
PGPASSWORD=<password> bash scripts/backup_db.sh
```

Con directorio y bucket personalizados:

```bash
PGPASSWORD=<password> \
BACKUP_DIR=/var/backups/ruta \
BACKUP_BUCKET=ruta-backups-prod \
bash scripts/backup_db.sh
```

**Salida esperada:**

```
=== Backup BD RUTA ===

Host    : 149.130.168.24:26432
BD      : rutadb  (schema: ruta)
Archivo : ./ruta_backup_20260101_030000.dump

Ejecutando pg_dump...

✓ Backup completado exitosamente.
  Archivo : ./ruta_backup_20260101_030000.dump
  Tamaño  : 2.4M

Listo.
```

El archivo generado tiene el formato `ruta_backup_YYYYMMDD_HHMMSS.dump` (formato custom de pg_dump, óptimo para restore selectivo y compresión).

---

## Verificar backup

Antes de un restore, verificar que el archivo es válido listando su contenido:

```bash
PGPASSWORD=<password> pg_restore --list ruta_backup_20260101_030000.dump | head -30
```

Esto imprime el índice del backup sin conectar a la BD. Si el comando retorna una lista de objetos (tablas, índices, secuencias), el archivo está íntegro.

Para verificar la conectividad con la BD destino antes de restaurar:

```bash
PGPASSWORD=<password> psql -h 149.130.168.24 -p 26432 -U ruta -d rutadb -c "SELECT version();"
```

---

## Ejecutar restore

> **Advertencia:** El restore sobreescribe todos los datos actuales del schema `ruta`. Esta operación no se puede deshacer. Toma un backup nuevo antes de restaurar si hay datos en producción que quieras conservar.

```bash
PGPASSWORD=<password> bash scripts/restore_db.sh ruta_backup_20260101_030000.dump
```

El script pedirá confirmación explícita (escribir `si`) antes de proceder. Tras el restore ejecuta automáticamente una verificación de filas en tablas clave (`users`, `orders`, `clients`).

**Salida esperada tras restore exitoso:**

```
─────────────────────────────────────────────
Conteo de filas en tablas clave (schema ruta):
─────────────────────────────────────────────

  Tabla                Filas
  -------------------- -----
  users                42
  orders               318
  clients              5

✓ Restore completado exitosamente.
```

---

## Política de retención

| Frecuencia  | Retención         |
|-------------|-------------------|
| Diario      | Últimos 30 backups |
| Semanal     | Últimos 4 backups  |

Aplicar esta política eliminando archivos antiguos del bucket después de cada backup automatizado:

```bash
# Ejemplo AWS S3: eliminar backups diarios con más de 30 días
aws s3 ls s3://ruta-backups-prod/ \
  | awk '{print $4}' \
  | sort \
  | head -n -30 \
  | xargs -I {} aws s3 rm s3://ruta-backups-prod/{}
```

---

## Frecuencia recomendada

- **Backup diario automático** — ejecutar a las 3:00 AM via cron o scheduler de OCI/AWS.
- **Backup antes de cada migración** — ejecutar manualmente antes de aplicar cualquier `ALTER TABLE`, `DROP`, o script de migración Drizzle.

Ejemplo de cron para backup diario:

```cron
0 3 * * * PGPASSWORD=<password> BACKUP_DIR=/var/backups/ruta bash /ruta/infra-ruta/scripts/backup_db.sh >> /var/log/ruta_backup.log 2>&1
```

---

## Restore de emergencia

Procedimiento paso a paso para un restore en producción:

1. **Conectar al servidor** donde está disponible `pg_restore` y acceso a la BD.

2. **Identificar el backup** a restaurar (el más reciente o el solicitado):
   ```bash
   ls -lht /var/backups/ruta/ | head -10
   # o listar desde el bucket:
   aws s3 ls s3://ruta-backups-prod/ --recursive | sort | tail -10
   ```

3. **Descargar el backup** si está en un bucket remoto:
   ```bash
   aws s3 cp s3://ruta-backups-prod/ruta_backup_20260101_030000.dump .
   # o con OCI CLI:
   oci os object get --bucket-name ruta-backups-prod --name ruta_backup_20260101_030000.dump --file ruta_backup_20260101_030000.dump
   ```

4. **Verificar integridad** del archivo:
   ```bash
   PGPASSWORD=<password> pg_restore --list ruta_backup_20260101_030000.dump | wc -l
   ```
   Debe retornar un número mayor a 0.

5. **Notificar al equipo** antes de ejecutar el restore (canal de incidentes).

6. **Tomar un backup del estado actual** (si la BD aún está accesible):
   ```bash
   PGPASSWORD=<password> bash scripts/backup_db.sh
   ```

7. **Ejecutar el restore**:
   ```bash
   PGPASSWORD=<password> bash scripts/restore_db.sh ruta_backup_20260101_030000.dump
   ```

8. **Verificar la aplicación** — levantar el backend y ejecutar las pruebas de humo:
   ```bash
   curl -f http://localhost:3000/health
   ```

9. **Documentar el incidente** — registrar fecha, causa, backup usado, y tiempo de restauración.
