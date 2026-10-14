<!-- One item, one pull request. The method is docs/AGENTS.md and it is not optional. -->

## What was found

<!-- The bug, the run that found it (date, machine class, phase or command), or the gap. Not the symptom: the class. -->

## What this changes

<!-- One or two sentences. If it changes how something is designed rather than fixes it, say so: those start as an issue. -->

## The proof

- [ ] The check that covers it: `verify/checks/NNN-….sh` (new or extended), one file, one verdict.
- [ ] Its tooth: `verify/teeth/NNN.sh` mutates the tree the way the real regression would, and the check turns red. `./bin/aegis verify --teeth NNN` says "they all bite".
- [ ] `./bin/aegis verify --profile both` is ALL PASS on this branch.
- [ ] The product names no machine and no person (checks 116 and 117).

## What a live instance has to do

<!-- Nothing, or the exact commands (`aegis seed apply <path>`, `aegis init --only NN`, a sync). If this has not run on an instance yet, say "not yet run on a live instance" here and in CHANGELOG.md. -->
