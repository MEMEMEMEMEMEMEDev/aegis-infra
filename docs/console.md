# The console

A visual layer over the CLI, built **on top of it and not instead of
it**. Every screen is drawn from the documents the commands already
emit; the console measures nothing of its own, and there is no command
it can run that you cannot.

It has **no AI agent**, and that is a decision rather than an omission.
A platform whose job is to say what is true about your machine does not
get to guess.

```bash
aegis console serve            # http://127.0.0.1:7391
```

## The four states, which is the whole point

Every reading on every screen carries one of four states, and the
fourth is the reason the console exists:

| on the screen | what it means |
|---|---|
| **fine** | measured, and nothing is being asked of anybody |
| **wrong** | measured, and something is off |
| **attention** | measured, and somebody has a decision to make |
| **unseen** | **nobody could look** |

Almost every dashboard has two states and paints the third and fourth
green. «No failures found» and «I could not reach the thing» look
identical, and only one of them gets investigated. Here `unseen` is the
only state with no colour of its own: it is hatched, and it is drawn
first.

The state travels in a `data-state` attribute and never in a word, so
the text on screen can be reworded or translated without any check
noticing — and what may never change quietly is which state a thing IS.

## What it reads

Six commands, each one asked for its document (`--json`), and a source
that cannot answer is a **reading too** — never a spinner, never a blank
panel:

| source | the question it answers |
|---|---|
| `aegis org list` | which organizations exist, as their contracts declare them |
| `aegis traffic show` | what actually arrived at each one |
| `aegis capacity show` | does another organization fit, and what runs out first |
| `aegis builds show` | what happened to each push, link by link |
| `aegis check` | the round: the cluster against what is declared |
| `aegis repos list` | what each service is written in, and which repositories nothing runs yet |
| `aegis edge check` | do the hostnames anybody types exist and answer |

The first screen leads with **your organizations**, each service carrying
the language GitHub already measured for its repository — the contract
says `http`, which is what a service is to the platform, and never what
it is written in. Below them, the repositories **nothing is running
yet**, which is the list somebody needs in front of them to take one on,
and every one of them opens the new-organization form already filled in.

Beside each language is a dot in **GitHub's own colour for it**, which
arrives in the same answer as the name. It is a dot and not a logo on
purpose: the elephant, the gopher and the elePHPant are trademarks with
usage policies, and a platform whose whole argument is «measured, and it
says where it got it» does not redistribute somebody else's mark. The
typefaces this console ships could be mirrored because the OFL says so
out loud. A language nobody could measure gets **no dot at all** rather
than a grey one — an absent mark reads as «no language», and a grey one
reads as a language that happens to be grey.

## One organization

`/org/<name>` is that organization and nothing else — its sources are
scoped at the command (`aegis tenant show <name>`,
`aegis traffic show --org <name>`, `aegis data remote status --org
<name> --json`) rather than filtered from the instance's documents,
because a screen that filtered would be dropping measurements.

It shows its namespace, one line per declared service against the
workload actually running, the volume of each database, whether each
public path is routed **and has anybody behind it**, how much of the
quota is spent, and how old the off-site copy is against the cadence
this instance actually keeps.

And it names **what the contract does not declare**: a workload nobody
claims, a volume nobody claims. That matters more than it sounds. The
contract is what every tool here derives from, so anything the contract
does not name is invisible to all of them at once — including
`aegis data`, which reads contracts.

The two are not the same finding. aegis governs what **runs**, so an
undeclared workload escapes the size policy, the NetworkPolicies and the
quota's intent, and it is reported as wrong. An undeclared **volume** is
named and is not: whether what is inside it matters is something only
its owner knows, and a disk deliberately kept outside a contract is a
decision somebody already made. The row says the volume is there and
that nothing copies it, and the person decides. The sentence is the
alarm, not the colour.

## What it writes

Files in this instance, and nothing else, ever.

`/new` describes an organization and writes nothing. You can start from
one of your own repositories — the list of the ones nothing is running
is right there, and picking one fills the form with what was measured
about it, its name and the URL GitHub itself returned, plus **one
suggestion** for the type that the form says is a suggestion. What the
form submits is a proposal; the next screen is `aegis org plan`, and
that writes nothing either. Only then is there a button.

The button does three things, and all three only write files here: the
contract into `orgs/`, the manifests (`aegis org apply`) and the
encrypted secrets that are missing (`aegis secret create`). `aegis org`
promises it does not talk to the cluster in its own module, and
`aegis secret` never invokes kubectl at all, so taking them on changes
no promise this console had already made.

Then it shows the **three steps that are left, and why each one is
left**: your commit, because that is what makes a file in a working tree
harmless; `aegis sync root`, because it speaks to the cluster; and
`aegis app apply`, because it creates a repository, a deploy key and a
webhook on GitHub, which is somebody else's machine.

It does not commit, it does not push, it does not apply, and it does not
touch the cluster. That is what makes the file harmless: **ArgoCD reads
the remote**, so nothing runs until you commit. It is the property
`aegis org` already has — the worst that can happen is an ugly diff
nobody commits — and the console inherits it verbatim.

It refuses to write over a contract that exists. Creating an
organization that is already there is an edit, and an edit is a
different decision — it has its own door.

### Changing one

`edit the contract`, from an organization's own screen. The form opens
filled in with what is there, the plan shows the **diff of the contract
itself** before the list of generated files, and the button says it will
write over it.

Three things it will not do, and they are the whole reason it is a
separate door:

- **It does not remove a service.** A form with fewer rows than the
  contract has services would delete the rest, silently, at the moment
  somebody pressed save — and a database being removed takes its volume
  with it. Removing one is `aegis org` by hand, which says what it is
  about to do first.
- **It does not rename.** That would write a second contract and leave
  the first one where it is: two files, one namespace, and a screen that
  says it saved.
- **It does not create.** A create arriving disguised as an edit skips
  every question the create screen asks.

And what it changes is **only what it shows**. The form has six fields
per service; a contract carries more — `usa`, the storage block, the
whole `ai` section with its tasks — and all of it comes out the other
side exactly as it went in. The current contract is the floor and the
form is applied on top of it, rather than the contract being rebuilt
from the form.

Every choice the form offers is derived from `aegis org schema`, which
derives from the validator itself; and the validator is what refuses,
**in its own words**, at whatever length it takes. There is no
JavaScript anywhere in the console, so a field cannot be greyed out as
you change a type: the rules travel as text beside each type instead.

## Reaching it, and why it is not published

The console binds `127.0.0.1` and there is no flag to change it. From
another machine:

```bash
ssh -L 7391:127.0.0.1:7391 you@your-server
```

It is **not published through the tunnel**, and not for lack of trying:
the tunnel has a single `ingress_service` pointing at traefik inside the
cluster, cloudflared runs inside the cluster, and the console runs on
the host because it needs the age key, the `gh` session and kubectl. A
second connector does not help — the connectors of one tunnel are
interchangeable and Cloudflare spreads traffic across them. Publishing
it is a tunnel of its own with a connector on the host.

## What the guard does, and what it is not

It is **not authentication and does not pretend to be**. Anything already
running as your user can read the age key and the kubeconfig directly
and has no need of a console. What the rules stop is a **remote page**
borrowing your browser as a way in, which is a different and entirely
real thing:

- **Every request** must be addressed to a loopback name. A page whose
  domain starts resolving to `127.0.0.1` keeps its own origin — the
  same-origin policy is not violated, it simply does not apply — and the
  `Host` header is the only thing that gives it away.
- **Every write** must carry an `Origin` of this console's own, a
  `Sec-Fetch-Site` that is not cross-site, and a token this process
  minted at start-up. Cross-origin form POSTs have never been blocked by
  the same-origin policy; the defence is that an attacking page can send
  a request and cannot read the answer, so it never learns the token.

The page itself is served under `default-src 'none'` with no
`script-src`, `form-action 'self'` and `frame-ancestors 'none'`. It
fetches nothing, not even its own typefaces, which are inlined.

## The corpus

`console/cases/` holds states of the world as the commands really
emitted them, and the console is built until they render correctly.
Every case declares its provenance — `medido`, `derivado` from a
recorded mutation, or `sintetico` saying why — and none of them carries
anything that identifies the instance it came from.

```bash
aegis console list                        # the corpus
aegis console capture NAME --what "..." --run "check" --run "edge check"
```

The capture masks two kinds of identity: every value of this instance's
`aegis.conf` that differs from the example, and **every repository of
the account that no contract declares**. The second was added on
2026-09-13, after the first capture of `aegis repos list` put
forty-three repository names into a case in one go and thirty-two of
them were private work that merely lives in the same account.

The checks over it hold two invariants for every case: **no state is
lost and none is invented**, and **the verdict is never kinder than its
readings**.

## What is not there yet

- **Removing.** The console adds and changes; it never takes anything
  away. Removing a service, or an organization, is `aegis org` by hand.
- **Somebody else's console.** A person who is not the operator looking
  at their own organization needs Cloudflare Access and a tunnel of its
  own, and today Access admits a single email address. That is the
  original mission and it is still ahead.
