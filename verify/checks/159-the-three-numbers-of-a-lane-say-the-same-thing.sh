# title: the three numbers of a lane say the same thing
# origin: new in v3 — 2026-08-31, closing a citation the manifests had been making for two days
check() {
# Three manifests describe the SAME lane from three sides, and each one
# carries a number the other two also carry. They are already asserted
# in prose — `engine-llm.yaml` says «check 159 crosses them so the
# disagreement cannot be committed», `engine-mt.yaml` says the two move
# together, `gateway.yaml` says SAME NUMBER — and until today no check
# existed. A comment that names a check that does not exist promises a
# guarantee nobody gives.
#
# What each disagreement costs, which is why they are worth crossing:
#
#   · MODEL. The gateway asks the engine for the model the routing
#     promised, BY NAME (`--served-model-name`). If they drift, every
#     request fails at the engine with «a model nobody serves» — and
#     the manifests look perfectly reasonable read one at a time.
#   · IN FLIGHT. The gateway admits N at once and the engine accepts
#     N at once. If the gateway's number is the larger, the surplus
#     queues INSIDE the engine, where the gateway cannot see it: the
#     wait it reports stops being the wait there is.
#   · CONTEXT. A routing that offers more context than the engine
#     accepts is a 400 the caller can do nothing about. So the engine's
#     `MAX_MODEL_LEN` has to be at least the largest `contexto_max`
#     routed to that lane — greater is fine, smaller is a promise the
#     platform cannot keep.
#
# The lanes are DERIVED from the gateway's own variables (`AI_MODELO_*`
# names the lane) and never listed here: the day a fourth lane is
# added, it is measured without touching this file.
AI="$SEED/platform/k8s/base/ai-system"
[[ -d "$AI" ]] || { skip "there is no ai-system in the seed"; return; }

OUT="$(python3 - "$AI" "$SEED/platform/ai/routes.yaml" <<'PY'
import re, sys, pathlib, yaml
ai, routes_p = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

def cm(path):
    """The ConfigMap data of a manifest, whatever else it carries."""
    out = {}
    if not path.is_file():
        return out
    for d in yaml.safe_load_all(path.read_text(encoding="utf-8")):
        if isinstance(d, dict) and d.get("kind") == "ConfigMap":
            out.update(d.get("data") or {})
    return out

gw = (ai / "gateway.yaml").read_text(encoding="utf-8") if (ai / "gateway.yaml").is_file() else ""
# lane -> declared model, from the gateway's env. AI_MODELO_LLM -> llm.
lanes = {m.group(1).lower(): m.group(2)
         for m in re.finditer(r"AI_MODELO_([A-Z]+),\s*value:\s*\"([^\"]+)\"", gw)}
inflight = {m.group(1).lower() or "llm": m.group(2)
            for m in re.finditer(r"AI_EN_VUELO(?:_([A-Z]+))?,\s*value:\s*\"([^\"]+)\"",
                                 gw.replace("AI_EN_VUELO,", "AI_EN_VUELO_LLM,"))}
if not lanes:
    print("FAILno lane could be derived from the gateway's AI_MODELO_* variables: "
          "the check lost its subject and is NOT reporting that as a pass")
    raise SystemExit

# engine manifest per lane: engine-<lane>.yaml, the house's own naming.
ctx_wanted = {}
try:
    r = yaml.safe_load(routes_p.read_text(encoding="utf-8")) or {}
    for cap in (r.get("capacidades") or {}).values():
        e, c = cap.get("engine"), cap.get("contexto_max")
        if e and c:
            ctx_wanted[e] = max(ctx_wanted.get(e, 0), int(c))
except Exception as e:
    print(f"FAILai/routes.yaml could not be read ({e!r}): no context promise could be crossed")

print("    %d lane(s) derived from the gateway · %d routed context promise(s)"
      % (len(lanes), len(ctx_wanted)))

for lane, model in sorted(lanes.items()):
    d = cm(ai / f"engine-{lane}.yaml")
    if not d:
        # cpu is served by its own module and has no vLLM ConfigMap
        if lane == "cpu":
            continue
        print("FAIL%s: the gateway declares the lane and there is no engine-%s.yaml "
              "with a ConfigMap to cross it against" % (lane, lane))
        continue
    served = d.get("SERVED_NAME")
    if served != model:
        print("FAIL%s: the gateway asks for %r and the engine serves %r — every "
              "request would fail at the engine with a model nobody serves"
              % (lane, model, served))
    want, have = inflight.get(lane), d.get("MAX_NUM_SEQS")
    if want and have and want != have:
        print("FAIL%s: the gateway admits %s at once and the engine accepts %s — the "
              "surplus queues inside the engine, where the gateway cannot see it, and "
              "the wait it reports stops being the wait there is" % (lane, want, have))
    need, mml = ctx_wanted.get(lane), d.get("MAX_MODEL_LEN")
    if need and mml and int(mml) < need:
        print("FAIL%s: the routing promises %s of context and the engine accepts %s — "
              "a 400 the caller can do nothing about" % (lane, need, mml))
PY
)" || { fail "the crossing of the lanes could not be completed"; return; }
printf '%s\n' "$OUT" | grep -v '^FAIL'
if printf '%s\n' "$OUT" | grep -q '^FAIL'; then
    fail "a lane's numbers disagree: $(printf '%s\n' "$OUT" | sed -n 's/^FAIL//p' | paste -sd'; ')"
else
    pass "every lane serves the model the gateway asks for, admits the same number in flight, and accepts at least the context its routing promises"
fi
}
