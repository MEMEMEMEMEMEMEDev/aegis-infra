# title: the chart pins have no mirror in group_vars
# origin: verify-static.sh (v2) ══ 12, part b — split in v3
check() {
# The pins live in ONE place. A mirror in group_vars is two truths
# about the same version, and which one wins depends on who runs
# first.
# nc and not a bare grep: the comment that EXPLAINS why there are no
# chart_pins here also contains the word. The control of its own tooth
# found it out — mention ≠ use, the class of checks 22, 25, 66 and 71,
# and now of this one too.
nc "$P/ansible/inventory/group_vars/all.yml" | grep -q 'chart_pins' \
    && fail "chart_pins came back in group_vars (mirror forbidden)" \
    || pass "no chart pins mirror in group_vars"
}
