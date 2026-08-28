# Contributing

The method is in `docs/AGENTS.md` and it is not optional. In short:

1. **One item, one commit** (Conventional Commits). The message says
   what was found and why the fix attacks the class, not the symptom.
2. **Every fix or feature carries its check** in `verify/checks/` —
   one file, one verdict.
3. **Every check is proven with its tooth** in `verify/teeth/`: mutate
   the tree the way the real regression would, and watch the check
   fail. A check that does not bite does not exist.
4. **`./bin/aegis verify --profile both` is ALL PASS before you
   commit**, and `--teeth NNN` for the checks you touched.
5. Nothing is *done* until a run validates it on a real instance.
   `docs/journeys/foreign-instance.md` is how such a run is made.

The product is written in English — identifiers, comments, messages,
the seed, the docs — and `docs/glossary.md` decides which word stands
for which idea. The product names no machine and no person: no
addresses, no accounts, no home paths. Two checks enforce that and
will tell you if you slip.

If you want to change how something is designed rather than fix it,
open an issue first: the design journeys under `docs/` explain the
decisions, and most of them have a run behind them.
