# title: the seed is pure artifact — no bin/ and no executables
# origin: V-134 (02 §1) — new in v3
check() {
# Half of v2's debt came from the same code living in two places
# (seed/platform/bin/ and platform/bin/) and a whole tool being needed
# to watch that the copies did not drift apart.
# F1-F4 measured it: 3 of 12 commands travelled, the generator was 444
# lines behind, and the failure showed up «on another machine, not
# here». v3 does not watch the copy: it removes it. The code lives in
# the product.
D134=""
[[ -d "$P/bin" ]] && D134="$D134 seed/platform/bin/ came back (the code lives in libexec/, not in the artifact);"

# DECLARED EXCEPTION, with its reason and its date — a written exception
# is different from a hole: tofu/tofu-apply.sh is the wrapper that
# decrypts the secrets and runs tofu FROM the tofu directory, and the
# operator invokes it by hand from platform/tofu/ (the vps-lab
# protocol). Moving it to libexec/ changes the resolution of -chdir
# (#46) and of the secrets: it is a design decision, not a cleanup.
# The copy is still looked after by `aegis dev seed diff`, which covers tofu/.
# TO VERIFY (2026-08-23, T-02): decide whether it becomes `aegis tofu`.
EXCEPTIONS=("tofu/tofu-apply.sh")
while IFS= read -r f; do
    rel="${f#"$P/"}"
    for e in "${EXCEPTIONS[@]}"; do [[ "$rel" == "$e" ]] && continue 2; done
    D134="$D134 $rel is executable inside the artifact and is not declared;"
done < <(find "$P" -type f -perm -u+x)

# and the other side of the coin: the declared exceptions MUST exist,
# or the list turns into folklore.
for e in "${EXCEPTIONS[@]}"; do
    [[ -f "$P/$e" ]] || D134="$D134 the declared exception $e no longer exists (take it off the list);"
done
if [[ -n "$D134" ]]; then fail "seed with code:$D134"
else pass "the seed carries no bin/ and no undeclared executables (the code lives in the product)"; fi
}
