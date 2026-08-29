# Protocol: opening a repository to the public

Status: written on 2026-08-29, the morning after the first automated
alert on a repository of this project. It is not theory: every step
below is either something that was run that morning, or something whose
absence is what made that morning long.

The subject is the moment a repository stops being private. That moment
is irreversible in a way nothing else in this stack is: a `git push
--force` does not un-publish a blob somebody already cloned, and a
deleted repository does not un-publish it either. Everything here
therefore happens BEFORE, and what is measured is the whole history, not
the tree.

---

## 1. The scanners read the HISTORY, not HEAD

A clean working tree proves nothing. The interesting object is the one
that was committed and then removed in the next commit: it is not in
`HEAD`, it is not in `git status`, and it is one `git show` away from
anybody who clones. Both scanners have to be pointed at every reachable
commit, explicitly, because neither does it by default.

```sh
gitleaks detect --source . --log-opts=--all --redact -v
trufflehog git file://.
```

Three details that are not decoration:

- **`--log-opts=--all`**. Without it gitleaks walks the current branch.
  With it, every ref: other branches, tags, and the commits a rebase
  left behind but a ref still holds.
- **`--redact`**. The report is a file, and a report that quotes the
  finding in full is a second copy of the secret, living somewhere
  nobody is guarding. Read the location and the rule name; go to the
  blob for the value, once, if the triage really needs it.
- **verification**. trufflehog's value over a regex is that it ASKS the
  issuer whether the candidate still authenticates. A verified finding
  is not a hypothesis, it is a live credential and the triage below has
  only one branch. The flag that filters verified-only has changed
  spelling between versions: ask the binary (`trufflehog git --help`),
  do not copy it from a document, this one included. The rule of the
  house applies here as everywhere — the binary decides, the doc is a
  hypothesis.

Record the versions you ran. A scan is evidence only if a later reader
can tell which rule set produced it.

## 2. The identity sweep

A credential is not the only thing that must not be published. An
artifact that names one machine or one person is an artifact that was
written for that machine and that person, and it stops being something
anyone can install. Three checks already hold this line and they run
with everything else:

```sh
aegis verify --only 116 --only 117 --only 151
```

- **116** — no public address of a concrete machine, and no node name
  that is not the same on every installation.
- **117** — no absolute path under a home directory, and not the login
  or the hosting account of whoever is building the artifact. This one
  is deliberately RELATIVE: it reads the identity of the machine it runs
  on, so it catches whoever is standing there.
- **151** — nothing with the shape of a credential.

What the checks cannot ask, because it has no fixed shape, is asked by
hand, once, and over the history as well as the tree:

```sh
# the tree
git grep -nI -e "$(id -un)" -e "$(hostname)" -e "$YOUR_DOMAIN"
# every commit that ever existed on a ref
git grep -nI -e "$(id -un)" $(git rev-list --all)
# and the reverse question: when did this string enter and leave?
git log --all -p -S'<the string>'
```

The list of what to look for: personal names and logins, e-mail
addresses, the domain the instance runs under, public IP addresses,
absolute paths under a home directory, machine and node names, the names
of backup files, and the account names of any third-party panel. The
private record of the project — the plan, the decisions, the run
journals — is written in the other repository ON PURPOSE and stays
there; the product carries none of it.

## 3. What to do with a finding

There are two roads and they are not symmetric. **Rotating is the
default.** Declaring a false positive is the comfortable answer, and it
is therefore the one that must cost more evidence, not less.

**Road A — it is a credential. Rotate it.** The work is bounded and it
is mechanised: `aegis rotate --yes <name>` regenerates, syncs, and then
VERIFIES against the real consumer (without `--yes` it is a dry run that
shows the blast radius first), and `aegis rotate check <name>` asks
whether a credential still works without touching it. What closes the
finding is
not the rotation, it is three pieces of evidence:

1. the issuer says the old value no longer authenticates (its own
   console or API, not our inference);
2. the platform still works with the new one — the verifier that goes
   with that credential is green, and the point of it going through the
   real consumer is exactly this;
3. if the value is still reachable in the history, the history is
   rewritten and the forks and clones are accounted for. Rotation makes
   the published value worthless, which is what actually matters;
   rewriting is hygiene on top of that, never instead of it.

**Road B — it is not a credential.** To close a finding this way, three
pieces of evidence too, and they are heavier:

1. say what the string IS, in one sentence a stranger can check with a
   `grep` you write down;
2. show it is not the credential it resembles: compare it against every
   entry of the encrypted store by digest, and attempt a real login with
   it and watch the service REJECT it. "It looks harmless" is not
   evidence;
3. remove the string anyway, if anything can be minted in its place.

That last point is the one the case below turned into a rule. The output
of road B is not a marker telling the scanner to look away: it is a tree
that no longer contains the thing. `.gitleaks.toml` at the root is for
what genuinely cannot be removed — a filename, a format written out in a
comment — and each of its entries carries the reason and is scoped to
one line of one file (`paths` AND `regexes`), never to a whole path. A
waived file is a file where the next real leak lands in silence.

## 4. Turn the hosting platform's own scanning on

Before the repository goes public, and not after:

- **secret scanning**, so the platform tells you what it finds in what
  is already there;
- **push protection**, so it refuses the push that would add the next
  one. This is the only control on the list that acts BEFORE the
  irreversible moment, which makes it the most valuable one;
- alerts routed somewhere a person actually reads.

These are the platform's, not the artifact's, and they do not replace
the scans of §1: they run rules the platform chose, over what it can
see. Two instruments that disagree is a fine outcome; one instrument
that nobody checked is not.

## 5. The case that produced this protocol

An automated scanner reported a "Bearer Token" in a public repository of
this project. Two scanners were run over the whole history, and every
candidate was compared by digest against the encrypted store.

The finding was a FALSE POSITIVE, and what it actually was is the
interesting part: three deliberately WRONG passwords, written literally
in the rotation tool, used by its NEGATIVE teeth — the half of each
verifier that proves a service REJECTS a bad credential. Without that
half, a service that accepted anything would come out green. They had
never opened anything; they existed in order not to.

Three things were learned, and all three are rules now:

- **Proving a negative is unbounded work.** The rotation of a credential
  is a known amount of work with a verifier at the end of it. Showing
  that a string is NOT a credential took a morning of forensics, and the
  reader of the public repository cannot run that forensics at all: for
  them the string stays credential-shaped forever.
- **The workaround was more dangerous than the finding.** The first fix
  was an inline marker telling the scanner to skip those lines. The
  marker had to be appended to the end of a continued shell line, where
  a backslash followed by a space is an escaped space and NOT a
  continuation: the comment swallowed the rest of the command, and the
  three calls the marker was protecting had been dead since the moment
  it was added. A verifier that cannot fail is worse than no verifier.
  Suppression is a change to code, and it breaks code.
- **A test does not need a literal.** The wrong credential is now MINTED
  at run time — random bytes, in a file in tmpfs, consumed the way the
  real one is — so the tree carries none. Check 151 turns the next
  literal red, in this repository, before anybody else's scanner sees
  it.

The identity sweep of §2 ran that same morning and found something the
credential scanners are blind to: the seed installed the cluster's node
under the name that node has on ONE machine. It had shipped for months,
and every installation would have printed a stranger's node name. Check
116 covers node names now. The lesson is that a scanner looks for
secrets, and identity is not a secret — it needs its own pass.

---

## The line, after all this

The scans of §1 are a moment; the checks are the ratchet. What holds
once this protocol has been run is `aegis verify`: 116 for machines, 117
for people, 151 for credential shapes, each with teeth that prove it
still bites. Run the scanners again whenever the history is rewritten or
a new remote is added — those are the two events that change what is
published without changing the tree.
