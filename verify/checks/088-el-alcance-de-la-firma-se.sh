# title: el alcance de la firma se declara por ETIQUETA, jamás por lista (#14)
# origen: verify-static.sh (v2) ══ 88
check() {
# EL incidente del 2026-07-27, y el que #52 encontró todavía vivo en la
# semilla el 2026-08-11.
#
# El ClusterPolicy de firma scopeaba `namespaces: [org-personal]`. Se
# creó org-portafolio, se desplegó ahí, y esa organización nació FUERA
# del alcance de la verificación de firma. No hubo error, no hubo aviso,
# no hubo nada rojo: la política simplemente no la miraba. Se admitió un
# busybox público sin firmar y todo el tablero estaba en verde.
#
# Una lista de namespaces solo puede nombrar lo que ya existe. Cada
# organización nueva nace afuera por default, y "afuera" es invisible.
# La etiqueta invierte eso: la lleva el bundle de cada inquilino, así
# que la cobertura llega con la organización.
#
# ESTE CHECK NO EXISTÍA. La corrección se hizo en la instancia en #14 y
# la semilla siguió dos generaciones atrás durante quince días, con el
# agujero abierto, porque nada comparaba SIGNIFICADO — solo presencia de
# archivos. Se descubrió recién al mutar el scope a mano y ver que
# verify-static seguía en verde.
D88=""
POL88="$P/k8s/base/kyverno-policies/clusterpolicy-require-aegis-signature.yaml"
if [[ ! -f "$POL88" ]]; then
    D88="$D88 no existe el ClusterPolicy de firma;"
else
python3 - "$POL88" "$P" <<'PY' || D88="$D88 (ver detalle arriba);"
import sys, yaml, pathlib

pol, raiz = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
malo = []

policies = [d for d in yaml.safe_load_all(pol.open()) if d]
if not policies:
    print("    el ClusterPolicy no tiene documentos"); sys.exit(1)

etiquetas_de_alcance = set()
reglas = 0
for p in policies:
    for r in p.get("spec", {}).get("rules", []):
        if not r.get("verifyImages"):
            continue
        reglas += 1
        for grupo in (r.get("match") or {}).get("any", []) + \
                     (r.get("match") or {}).get("all", []):
            res = grupo.get("resources") or {}
            # (1) una LISTA de namespaces es el modelo viejo: lo que no
            #     esté enumerado nace afuera, y nadie se entera.
            if res.get("namespaces"):
                malo.append(f"la regla '{r['name']}' scopea por LISTA de namespaces "
                            f"{res['namespaces']}: toda organización nueva nace fuera "
                            f"del alcance de la firma sin una sola señal")
            sel = (res.get("namespaceSelector") or {}).get("matchLabels") or {}
            for k, v in sel.items():
                etiquetas_de_alcance.add((k, v))
            if not res.get("namespaces") and not sel:
                malo.append(f"la regla '{r['name']}' no acota a NADA: ni lista ni selector")

if reglas == 0:
    malo.append("ninguna regla con verifyImages: el check no evaluó nada")

# (2) y la etiqueta del selector la tiene que llevar ALGÚN Namespace del
#     artefacto. Un selector que no matchea nada scopea a cero: mismo
#     agujero, disfrazado de modelo nuevo.
if etiquetas_de_alcance:
    portadores = {}
    for f in raiz.rglob("*.y*ml"):
        try:
            docs = list(yaml.safe_load_all(f.open()))
        except Exception:
            continue
        for d in docs:
            # Hay YAML del artefacto cuya raíz es una LISTA (parches de
            # kustomize): d.get() reventaba con AttributeError y el check
            # moría en rojo sin haber medido nada.
            if not isinstance(d, dict) or d.get("kind") != "Namespace":
                continue
            labels = (d.get("metadata") or {}).get("labels") or {}
            for kv in etiquetas_de_alcance:
                if labels.get(kv[0]) == kv[1]:
                    portadores.setdefault(kv, []).append(d["metadata"]["name"])
    for kv in sorted(etiquetas_de_alcance):
        if not portadores.get(kv):
            malo.append(f"la etiqueta de alcance {kv[0]}={kv[1]} no la lleva NINGÚN "
                        f"Namespace del artefacto: la política scopea a cero pods")
        else:
            print(f"    alcance {kv[0]}={kv[1]} -> {sorted(portadores[kv])}", file=sys.stderr)

for m in malo:
    print(f"    {m}")
sys.exit(1 if malo else 0)
PY
fi
if [[ -n "$D88" ]]; then fail "alcance de la firma:$D88"
else pass "la firma scopea por etiqueta aegis-tenants y la etiqueta la lleva un Namespace real del artefacto"; fi
}
