# teeth of check 171 — a heavy build measures the room it needs before
# asking for it.

# THE STATE THE ARTIFACT WAS IN until 2026-09-01: nothing measured the
# node, and the GPU engine's build was evicted three times, each after
# fifteen or twenty minutes, reported as ABORTED.
red_1() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = re.sub(r'^\s*_room_gib="\$\(df[^\n]*\n', '', s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# an image whose build cost nobody wrote down: it cannot be refused
# before it is too late, and it is the heaviest one.
red_2() {
    sed -i 's/_job=engine-gpu   ; _to=14400 ; _gib=36/_job=engine-gpu   ; _to=14400/' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# measured, but AFTER firing — which is watching, not checking.
red_3() {
    python3 - "$AEGIS_ROOT/init/phases/87-ai.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'^\s*_room_gib="\$\(df[^\n]*\n(?:[^\n]*\n){0,6}?\s*fi\n', s, re.M)
blk = m.group(0)
s = s.replace(blk, "", 1)
# after the PIN, which is genuinely after the build. Putting it back
# just above `gate "ai-image-built-..."` left it on the line BEFORE the
# one holding jenkins_build_retry, so the mutation was inert and the
# tooth did not bite.
anchor = '        run_cmd "$AEGIS_ROOT/libexec/aegis-ai" images "$_img:$_tag"\n'
s = s.replace(anchor, anchor + blk, 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
}

# a refusal that says what is wrong and not what to do: it spends the
# reader's time twice, which is the thing this whole check is about.
red_4() {
    sed -i 's/Free space and run this phase again/No hay lugar/' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# control: PROSE about disk and evictions is how this decision is
# explained, and must not stand in for the measurement.
control_1() {
    printf '\n# note: kaniko writes its layers on the node; df tells you if they fit.\n' \
        >> "$AEGIS_ROOT/init/phases/87-ai.sh"
}

# control: another image with its cost declared is the shape working,
# not a defect.
control_2() {
    sed -i 's/aegis-engine-cpu) _job=engine-cpu   ; _to=3600  ; _gib=10 ;;/aegis-engine-cpu) _job=engine-cpu   ; _to=3600  ; _gib=10 ;;\n        aegis-engine-xpu) _job=engine-xpu   ; _to=3600  ; _gib=9 ;;/' \
        "$AEGIS_ROOT/init/phases/87-ai.sh"
}
