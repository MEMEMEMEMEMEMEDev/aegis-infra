# teeth for check 110 (every absent subsystem is declared)
#
# The real risk is not that AI is missing: it is that TOMORROW somebody
# takes out a subsystem and writes nothing. Until 2026-08-29 this red
# deleted the protocol that declared the ONE absence the seed had. The
# AI subsystem then came INTO the seed, the absence stopped existing,
# and this mutation started editing a file that was no longer there:
# it left the tree unchanged and the harness said so. Re-aimed at what
# the sentence always meant — take a subsystem OUT and stay quiet —
# which no longer needs an absence to pre-exist in order to be tested.
red_1() { rm -rf "$AEGIS_ROOT/seed/platform/k8s/base/ai-system"; }

# emptying the whole protocols folder: the same absence by another
# route, so the check does not depend on a file name.
red_2() { rm -rf "$AEGIS_ROOT/seed/platform/docs/protocols"; }

# and the case that really matters: a NEW subsystem taken out without
# documentation. If the check only watched AI, this would pass green.
red_3() {
    cat >> "$AEGIS_ROOT/lib/aegis/org.py" <<'PY'


QUEUES_K8S = os.path.join(PLATFORM_ROOT, "k8s", "base", "queue-system", "bundle.yaml")
PY
}

# control: writing MORE documentation cannot turn it red.
control_1() {
    printf '\n\n## Added note\n\nSomething more about k8s/base/ai-system/ and how it comes back.\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/ai-subsystem.md"
}

# The other direction, which is the one that ages without anybody
# looking: a declaration naming something that IS there. The same
# standard as `aegis dev seed`'s exclusion policy — a rule pruned by
# time stops protecting without warning, and a lie in the place where
# the truth is looked up is worse than having nothing written at all.
red_4() {
    printf '\n<!-- aegis-absent: k8s/base/garage-system -->\n' \
        >> "$AEGIS_ROOT/seed/platform/docs/protocols/ai-subsystem.md"
}
