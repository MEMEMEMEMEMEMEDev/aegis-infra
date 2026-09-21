# teeth for 225 — each red brings back a way a seed change missed an instance, or took what was hers.
C225="$AEGIS_ROOT/libexec/aegis-seed"
S225="$AEGIS_ROOT/lib/aegis/seed.py"
_s225() { python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}
# the copy goes bare: the seed's placeholders come back (2026-09-01)
red_1() { _s225 "$C225" '    seed_fetch "${paths[@]}"' '    for p in "${paths[@]}"; do cp "$AEGIS_ROOT/seed/platform/$p" "$PLATFORM_DIR/$p"; done'; }
# the pins are not written back: a seed apply downgrades the instance
red_2() { _s225 "$S225" '            window.rewrite(platform_dir, new,' '            return restored, gone
            window.rewrite(platform_dir, new,'; }
# the derived block is not put back
red_3() { _s225 "$S225" '    f.write_text(pat.sub(lambda m: theirs.group(0), now, count=1))
    return True' '    return True'; }
# what aegis org apply writes stops being the instance's
red_4() { _s225 "$S225" '    "k8s/argocd-apps/tenants.yaml", "k8s/bootstrap/appprojects-tenants.yaml",' '    "k8s/argocd-apps/tenants.yaml",'; }
# a moved pin reads as a seed change: the instance is asked to bring an old version over
red_5() { _s225 "$S225" '        if changed and all(PIN_LINE.search(ln) for ln in changed):' '        if False:'; }
# apply stops refusing the instance's files
red_6() { _s225 "$C225" '    if owned="$(PYTHONPATH="$AEGIS_ROOT/lib" python3 -m aegis.seed owns "$PLATFORM_DIR" "${paths[@]}")"; then :; else' '    if true; then :; else'; }
# apply pushes on its own
red_7() { _s225 "$C225" '    printf '"'"'%sread it (git -C %s show), then push it: ArgoCD reads the remote%s\n'"'"' "$gray" "$PLATFORM_DIR" "$reset"' '    git -C "$PLATFORM_DIR" push'; }
# a PEM the instance carries reads as a seed change
red_8() { _s225 "$S225" '    text = _PEM.sub(r"\1__PEM__", text)' '    pass'; }
# the per-site re-pin is gone: a copied file keeps the seed's older tag beside sixteen newer ones
red_9() { _s225 "$S225" '                    lines[i] = old_line + ("\n" if ln.endswith("\n") else "")' '                    pass'; }
# ── controls ──
control_1() { _s225 "$S225" '# GENERATED placeholders: rendered by a phase, not by the config' '# GENERATED placeholders (a phase writes them, not the config render)'; }
control_2() { _s225 "$S225" '    "k8s/base/ai-system/prompts.yaml", "mirror-images/trivyignore.yaml",' '    "k8s/base/ai-system/prompts.yaml", "mirror-images/trivyignore.yaml", "notes/*",'; }
