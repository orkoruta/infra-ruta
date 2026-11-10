#!/usr/bin/env python3
"""Aplica a los servicios de Render la configuración declarada en los render.yaml.

Los cuatro servicios de RUTA se crearon a mano en el panel y NO están
gestionados por un Blueprint, así que editar `render.yaml` no cambia nada por sí
solo. Este script cierra ese hueco: lee los dos blueprints del repo y empuja
buildCommand, startCommand, las variables con valor literal y las reglas de
`routes`. Los secretos (`sync: false`) no se tocan — ya están en el panel.

Uso:
    python3 infra-ruta/scripts/apply_render_config.py            # modo seco
    python3 infra-ruta/scripts/apply_render_config.py --apply

Requiere la clave de API en ~/.config/render/api_key (chmod 600).

Si algún día se adoptan los servicios en un Blueprint de verdad
(Panel → seleccionar servicios → «Generate Blueprint»), este script sobra.
"""
import json, os, sys, yaml

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEY = open(os.path.expanduser("~/.config/render/api_key")).read().strip()
DRY = "--apply" not in sys.argv

IDS = {
    "ruta-orko-api":   "srv-d8b6qf0js32c73fa9cag",
    "ruta-api-worker": "srv-d8k8jqrs9h5c73e3c9j0",
    "ruta-admin":      "srv-d8b6nfv7f7vs73bptjbg",
    "ruta-by-orko":    "srv-d8b6k3t7vvec73egvc70",
}


def call(method, path, body=None):
    """Vía curl: el Python de python.org en macOS no trae certificados raíz."""
    import subprocess
    cmd = ["curl", "-s", "-w", "\n%{http_code}", "--max-time", "60", "-X", method,
           "-H", "Authorization: Bearer " + KEY,
           "-H", "Content-Type: application/json",
           "-H", "Accept: application/json",
           "https://api.render.com/v1" + path]
    if body is not None:
        cmd += ["-d", json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    raw, _, code = out.rpartition("\n")
    return int(code), (json.loads(raw) if raw.strip() else None)


def services():
    for f in ("backend-ruta/render.yaml", "frontend-ruta/render.yaml"):
        for s in yaml.safe_load(open(os.path.join(ROOT, f)))["services"]:
            yield s


for s in services():
    name = s["name"]
    sid = IDS[name]
    static = s.get("runtime") == "static"
    print(f"\n=== {name} ({sid})")

    # 1. build / start command
    details = {"buildCommand": " ".join(s["buildCommand"].split())}
    if static:
        details["publishPath"] = s["staticPublishPath"].lstrip("./")
    else:
        details = {"envSpecificDetails": details}
        if s.get("healthCheckPath"):
            details["healthCheckPath"] = s["healthCheckPath"]
        details["envSpecificDetails"]["startCommand"] = s["startCommand"]
    print("  buildCommand/startCommand →", "DRY" if DRY else call("PATCH", f"/services/{sid}",
                                                                  {"serviceDetails": details})[0])

    # 2. variables con valor literal (los secretos sync:false no se tocan)
    for e in s["envVars"]:
        if "value" not in e:
            continue
        if DRY:
            print(f"  env {e['key']}={e['value']} → DRY")
        else:
            st, _ = call("PUT", f"/services/{sid}/env-vars/{e['key']}", {"value": str(e["value"])})
            print(f"  env {e['key']}={e['value']} → {st}")

    # 3. routes (solo estáticos)
    if s.get("routes"):
        payload = [{"type": r["type"], "source": r["source"], "destination": r["destination"]}
                   for r in s["routes"]]
        if DRY:
            print(f"  routes: {len(payload)} reglas → DRY")
        else:
            st, _ = call("PUT", f"/services/{sid}/routes", payload)
            print(f"  routes: {len(payload)} reglas → {st}")

print("\n" + ("MODO SECO — nada se cambió. Relanza con --apply" if DRY else "aplicado"))
