# teeth of check 281 — a webhook delivery is waited for the way GitHub
# delivers (alpha-ubuntu, 2026-10-12).
P35="$AEGIS_ROOT/init/phases/35-gitops.sh"
P60="$AEGIS_ROOT/init/phases/60-webhook.sh"
L281="$AEGIS_ROOT/lib/access.sh"

_sub() {   # <file> <old> <new> — exactly one occurrence, or the tooth is mis-aimed
    python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, "re-aim this tooth: " + sys.argv[2][:60]
p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))
PY
}

# phase 35 as it lost alpha-ubuntu: one finished delivery, polled
red_1() { _sub "$P35" '      hook_delivery_2xx "$GH_OWNER/$PLATFORM_REPO" "$HOOK_ID" "" "$DELIVERY_ID" 300' \
'      poll 180 5 bash -c "gh api repos/$GH_OWNER/$PLATFORM_REPO/hooks/$HOOK_ID/deliveries --jq .[0].status_code | grep -q ^2"'; }

# the wait that never sends again
red_2() { _sub "$L281" '                gh api -X POST "repos/$repo/hooks/$hook/deliveries/$did/attempts" >/dev/null 2>&1 \
                    || log_warn' '                true \
                    || log_warn'; }

# a 400 waited out to the timeout
red_3() { _sub "$L281" '            if [[ "$code" == 400 ]]; then' '            if false; then'; }

# any delivery counts, an old 2xx included
red_4() { _sub "$L281" 'if [[ "$did" =~ ^[0-9]+$ ]] && (( did > since )); then' 'if [[ "$did" =~ ^[0-9]+$ ]]; then'; }

# phase 60 without its mark
red_5() { _sub "$P60" 'hook_delivery_2xx "$GH_OWNER/$APP_REPO" "$HOOK_ID" push "$PUSH_SINCE" 300' 'hook_delivery_2xx "$GH_OWNER/$APP_REPO" "$HOOK_ID" push 0 300'; }

# a delivery in flight re-sent
red_6() { _sub "$L281" 'if [[ "$code" =~ ^[0-9]+$ ]] && (( (SECONDS' 'if (( (SECONDS'; }

# no pace: a redeliver on every lap
red_7() { _sub "$L281" '(( (SECONDS - t0) / ${AEGIS_HOOK_REDELIVER_S:-60} >= redelivered ))' 'true'; }

# the event ignored: a ping's 2xx passes for a push
red_8() { _sub "$L281" '    local t0=$SECONDS line did code redelivered=0 sel='"'"'.'"'"'
    [[ -n "$event" ]] && sel=' '    local t0=$SECONDS line did code redelivered=0 sel='"'"'.'"'"'
    [[ -n "" ]] && sel='; }

# phase 35 without its mark
red_9() { _sub "$P35" '"$HOOK_ID" "" "$DELIVERY_ID" 300' '"$HOOK_ID" "" 0 300'; }

# phase 60 marks AFTER the push
red_10() { _sub "$P60" '    PUSH_SINCE="$(hook_newest_delivery "$GH_OWNER/$APP_REPO" "$HOOK_ID" push)"
' '' && printf 'PUSH_SINCE="$(hook_newest_delivery "$GH_OWNER/$APP_REPO" "$HOOK_ID" push)"\n' >> "$P60"; }

# control: a LEGITIMATE change cannot turn it red
control_1() { printf '# legitimate comment\n' >> "$L281"; }
