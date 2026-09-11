# teeth for check 119 (every case says where it came from)
#
# Each red is a way a corpus rots: a case that lost its provenance, one
# that claims to be measured and cannot say what measured it, and —the
# one that matters— a derivation that no longer reproduces its base.
# None of them fails anywhere else: every document stays valid JSON and
# every screen would render exactly the same.

C119="$AEGIS_ROOT/console/cases"

# «this field is obvious» — and with it goes the only thing separating a
# capture from a file somebody typed
red_1() { sed -i '/^procedencia:/d' "$C119/round-with-findings/case.yaml"; }

# it still says `medido` and no longer says against which aegis: the
# measurement stops being repeatable and nobody can tell when it aged
red_2() { sed -i '/^aegis:/d' "$C119/round-with-findings/case.yaml"; }

# THE ONE THAT MATTERS: somebody touches up a derived document by hand.
# The mutation it declares no longer reproduces it, so the case is now
# a fiction wearing the word `derivado`.
red_3() { sed -i 's/1 expires in 12 days/1 expires in 3 days/' \
              "$C119/cert-expiring/documents/check.json"; }

# a command that produced neither a document nor a reason: the silence
# the whole corpus exists to make impossible
red_4() { python3 - "$C119/console-blind/case.yaml" <<'P'
import sys, pathlib, yaml
p = pathlib.Path(sys.argv[1]); c = yaml.safe_load(p.read_text(encoding="utf-8"))
c["producido_por"][0].pop("sin_documento")
p.write_text(yaml.safe_dump(c, sort_keys=False, allow_unicode=True), encoding="utf-8")
P
}

# a case that names a document it does not carry
red_5() { rm -f "$C119/contract-invalid/documents/org.json"; }

# ── controls: real changes that must NOT move the verdict ────────────

# a new MEASURED case appears, complete: it joins the corpus and stays green
control_1() { mkdir -p "$C119/probe-119/documents" \
    && printf '{"steps":[{"step":"x","state":"already"}],"rc":0}\n' > "$C119/probe-119/documents/edge.json" \
    && printf 'version: 1\ncaso: probe-119\nque: una captura mas\nprocedencia: medido\nproducido_por:\n- comando: edge check\n  documento: edge.json\n  rc: 0\nmedido_en: 2026-09-11T00:00:00-03:00\naegis: 5d89b79c5cd2a60e58241d1d24208179f8f5fec3\nforma:\n  edge.json:\n    claves: [rc, steps]\n    estados: [already]\n' > "$C119/probe-119/case.yaml"; }

# the sentence that describes a case is rewritten: prose, and it must
# not move a verdict about provenance
control_2() { sed -i 's/^que: .*/que: la ronda de una instancia en marcha, dicho de otro modo/' \
                  "$C119/round-with-findings/case.yaml"; }

# a SYNTHETIC case that says why the real state is out of reach: it is
# the deliberate exception the rule allows, and it has to pass
control_3() { mkdir -p "$C119/probe-119b/documents" \
    && printf '{"steps":[],"rc":2}\n' > "$C119/probe-119b/documents/edge.json" \
    && printf 'version: 1\ncaso: probe-119b\nque: un borde sin zona\nprocedencia: sintetico\npor_que: esta instancia no corre el perfil local y no hay otra donde medirlo\nforma:\n  edge.json:\n    claves: [rc, steps]\n    estados: []\n' > "$C119/probe-119b/case.yaml"; }
