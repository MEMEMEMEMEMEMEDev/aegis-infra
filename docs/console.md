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
| **could not look** | **nobody could look** |

Almost every dashboard has two states and paints the third and fourth
green. «No failures found» and «I could not reach the thing» look
identical, and only one of them gets investigated. Here «could not look»
is the only state with no colour of its own: it is hatched, its dot is
square, and it is drawn first.

The state travels in a `data-state` attribute and never in a word, so
the text on screen can be reworded or translated without any check
noticing. What may never change quietly is which state a thing IS.

## The screens

The console is organized the way people who arrive from Vercel, from
the AWS console or from GCP already think, and not the way the CLI is
written. A menu on the left in three groups (build and ship, run, platform),
one line per screen, and beside each line **a dot with the worst state
of what feeds it**, so that «something is wrong on Storage» is readable
before Storage is open. The first screen says it twice: the sentence
at the top, and under it the pages that are not fine, as links.

| screen | the question it answers | drawn from |
|---|---|---|
| **Projects** | which applications run here, what each one is, what reached it and what happened to its last push | `org list`, `repos list`, plus one line per screen below |
| **Deployments** | what happened to every push, link by link: built, scanned, signed, pinned | `builds show --last 60`, and the round's sections about CI |
| **Domains** | which hostnames the contracts declare, whether each exists at the edge, which service answers on each path | `edge check`, the contracts, and the round's sections about the edge and certificates |
| **Traffic** | what actually reached each project in the last 24 hours | `traffic show` |
| **Storage** | which projects hold data, where the disks are, and how old each off-site copy is against its clock | `data remote status`, the contracts, and the round's `backups` |
| **Plans** | what a project may take: each plan's sentence, its seven numbers, who names it, and how many more of it would fit | `quota list`, `capacity show` |
| **Security** | what runs is what was signed; what each service may reach; what this console itself does and does not do | the round's sections about the supply chain, `builds show`, the contracts |
| **Machine** | what is free, what is spoken for, how many more projects of each plan would fit | `capacity show`, and the round's sections about the node |
| **Health** | the round, whole: every section with every measure | `check`, `edge check` |

A project is one of your applications: its services, its domain, its
data. The contract in git says what it is; everything else on the
screen was measured. A **project card** carries the domain, one pill per
service with the language GitHub measured for its repository (a dot in
GitHub's own colour, never a logo), the requests and errors of the last
24 hours, and the last deployment with its four links.

The round has fourteen-odd sections and each belongs somewhere: the
ones about CI are drawn on Deployments, the ones about the edge on
Domains, `backups` on Storage, the node on Machine. Every screen that
shows some of them says **how many more there are on Health**, with the
worst of their states, so that five sections drawn never read as if the
other nine were fine. Health draws all of them.

### One project

`/projects/<name>` is that project and nothing else. Its sources are
scoped at the command (`aegis tenant show <name>`, `aegis builds show
--org <name>`, `aegis traffic show --org <name>`, `aegis data remote
status --org <name>`) rather than filtered from the instance's
documents, because a screen that filtered would be dropping
measurements. The tabs are anchors on one page:

- **Services**: what the contract declares against what is actually
  running in its namespace, one card per service with how many copies
  run, its kind, its language, its public path, its disk and the digest
  it runs. Then the routes with **who answers behind each path**, the
  usage of the plan on its tightest dimension, and **what is not in the
  contract**: a workload nobody claims, a volume nobody claims.
- **Deployments**: its last pushes, newest first.
- **Traffic**: its last 24 hours.
- **Storage**: its off-site copy, read against the clock this instance
  keeps.
- **Settings**: the contract as a person reads it, with the one button
  that opens the editor.

What the contract does not declare matters more than it sounds. The
contract is what every tool here derives from, so anything it does not
name is invisible to all of them at once, including `aegis data`, which
reads contracts. An undeclared **workload** is reported as wrong: it
escapes the size policy, the NetworkPolicies and the quota's intent. An
undeclared **volume** is named and is not: a disk deliberately kept
outside a contract is a decision its owner already made, and the row
says it is there and that nothing copies it. The sentence is the alarm,
not the colour.

### The words

The contract is written in the platform's own words. The screens
translate them, and the translation lives in one table
(`lib/aegis/screens.py`), so that a person never has to learn the
contract to read the screen:

| the contract says | the screen says |
|---|---|
| `estatico` | static site |
| `http` | web service |
| `worker` | background worker |
| `postgres`, `mongodb`, `redis` | PostgreSQL database, MongoDB database, Redis cache |
| `cuota: pequena` | plan `pequena`, described on Machine by what it asks for |
| `usa: [internet, postgres]` | may reach the internet, its PostgreSQL |
| `limits.cpu`, `requests.memory` | CPU ceiling, memory reserved |

The contract's word stays visible beside the translation wherever
somebody might have to type it back.

## What it reads

Nine commands, each one asked for its document (`--json`), and a source
that cannot answer is a **reading too**: never a spinner, never a blank
panel. It is drawn as «could not look», with the reason.

| source | the question it answers |
|---|---|
| `aegis org list` | which projects exist, as their contracts declare them |
| `aegis repos list` | what each service is written in, and which repositories nothing runs yet |
| `aegis traffic show` | what actually arrived at each one |
| `aegis capacity show` | does another project fit, and what runs out first |
| `aegis builds show --last 60` | what happened to each push, link by link |
| `aegis check` | the round: the cluster against what is declared |
| `aegis edge check` | do the hostnames anybody types exist |
| `aegis data remote status` | how old the off-site copy of each project is, against the clock |
| `aegis quota list` | the plans of the catalogue: words, numbers, who names each |

The console reads once when it starts, serves what it has, and reads
again when asked («Read it again», on every screen). Every reading is
drawn **with the time it was taken**, on the page and not only in an
attribute: a right number from forty minutes ago shown as if it were
now is the oldest lie a dashboard tells.

## What it writes

Files in this instance, and nothing else, ever.

`/new` describes a project and writes nothing. It opens with your
repositories that nothing runs yet; picking one fills the form with what
was measured about it, its name and the URL GitHub itself returned, plus
**one suggestion** for what it is, which the form says is a suggestion.

**The short path is the default.** Most projects are one repository
that is a static site or a web service, maybe with a database, so that
is what the screen asks for: what it is (three cards that say what each
kind is), where it comes from, what it needs (ticked: a PostgreSQL, a
Redis, a bucket, the internet), and which plan (picked by what it is
for). Ticking a database adds it to the project as a service the
platform provides and lets the web services and workers reach it; a
person never has to know that this means «a service of type postgres
named datos with `usa: [postgres]` on the API». The contract's own
words sit under every card, because the contract is what gets
committed.

The form puts `8080` in the port and `/` in the public path before
anybody types. Those two defaults, and only those, are left out of the
contract on the kinds that refuse them; anything typed over them
travels, and the validator refuses it by name.

**More services are one click away, as many as the plan holds.** «Add
another service» is a round trip that brings the form back with one
more row and everything typed still in place, because the console
serves no script. There is no fixed number: the plan preview says
whether they fit, and names the plan that would hold them when they do
not.

What the form submits is a proposal; the next screen is `aegis org
plan`, and that writes nothing either. It opens **in plain words**: the
project as sentences, one per service, to check against what you
meant, before the list of files that would be generated. Only then is
there a button.

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
`aegis org` already has, the worst that can happen is an ugly diff
nobody commits, and the console inherits it verbatim.

It refuses to write over a contract that exists. Creating a project that
is already there is an edit, and an edit is a different decision with
its own door.

### A plan of your own

The plan is picked on the form by **what it is for**: each one carries
the sentence its plan declares in `plans.yaml` and its seven numbers in
words. When none fits, «create a plan of your own» opens the second
thing the console writes.

A plan is a **named step in the catalogue**, and that is the whole
design: a contract names a plan and never a number, so changing the
machine is one file and not thirty contracts, and a plan with a name
can be counted and measured (Machine says how many more of each would
still fit). A new plan starts from one that exists, changes the numbers
you say, and goes through the same validation the shipped ones get,
through `aegis quota add`. The preview says how many projects of it the
machine would fit today; the button writes one block into `plans.yaml`,
keeping every comment in that file. No commit, no cluster.

The plans aegis ships keep their numbers: they are the vocabulary the
documentation speaks. Their sentence can be set; to «change» one, start
a plan of your own from it. The ones you add are yours to change and to
remove while no contract names them. Plans says which is which.

### Changing one

`Edit the contract`, from a project's own screen. The form opens filled
in with what is there, the plan shows the **diff of the contract
itself** before the list of generated files, and the button says it will
write over it.

Three things it will not do, and they are the whole reason it is a
separate door:

- **It does not remove a service.** A form with fewer rows than the
  contract has services would delete the rest, silently, at the moment
  somebody pressed save, and a database being removed takes its volume
  with it. Removing one is `aegis org` by hand, which says what it is
  about to do first.
- **It does not rename.** That would write a second contract and leave
  the first one where it is: two files, one namespace, and a screen that
  says it saved.
- **It does not create.** A create arriving disguised as an edit skips
  every question the create screen asks.

And what it changes is **only what it shows**. The form has six fields
per service; a contract carries more (`usa`, the storage block, the
whole `ai` section with its tasks) and all of it comes out the other
side exactly as it went in. The current contract is the floor and the
form is applied on top of it, rather than the contract being rebuilt
from the form.

Every choice the form offers is derived from `aegis org schema`, which
derives from the validator itself; and the validator is what refuses,
**in its own words**, at whatever length it takes. There is no
JavaScript anywhere in the console, so a field cannot be greyed out as
you change a kind: the rules travel as text beside each kind instead.

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
second connector does not help, because the connectors of one tunnel are
interchangeable and Cloudflare spreads traffic across them. Publishing
it is a tunnel of its own with a connector on the host.

## What the guard does, and what it is not

It is **not authentication and does not pretend to be**. Anything already
running as your user can read the age key and the kubeconfig directly
and has no need of a console. What the rules stop is a **remote page**
borrowing your browser as a way in, which is a different and entirely
real thing:

- **Every request** must be addressed to a loopback name. A page whose
  domain starts resolving to `127.0.0.1` keeps its own origin (the
  same-origin policy is not violated, it simply does not apply) and the
  `Host` header is the only thing that gives it away.
- **Every write** must carry an `Origin` of this console's own, a
  `Sec-Fetch-Site` that is not cross-site, and a token this process
  minted at start-up. Cross-origin form POSTs have never been blocked by
  the same-origin policy; the defence is that an attacking page can send
  a request and cannot read the answer, so it never learns the token.

The page itself is served under `default-src 'none'` with no
`script-src`, `form-action 'self'` and `frame-ancestors 'none'`. It
fetches nothing, not even its own typefaces, which are inlined.

## The corpus, and the screens without a server

`console/cases/` holds states of the world as the commands really
emitted them, and the console is built until they render correctly.
Every case declares its provenance (`medido`, `derivado` from a recorded
mutation, or `sintetico` saying why) and none of them carries anything
that identifies the instance it came from.

```bash
aegis console list                        # the corpus
aegis console capture NAME --what "..." --run "check" --run "edge check"
aegis console draw DIR --case instance-console --case project-shop
```

`draw` writes **every screen of a case** into a directory as plain HTML
files: the console with no server, no cluster and no browser needed to
produce it. It is how the screens are designed, looked at and redrawn,
and because a case is anonymised by construction, what comes out can be
shown to anybody. Naming an instance case and a project case together
draws both, and the project's page gets the instance as its context.

The capture masks two kinds of identity: every value of this instance's
`aegis.conf` that differs from the example, and **every repository of
the account that no contract declares**. The second was added on
2026-09-13, after the first capture of `aegis repos list` put
forty-three repository names into a case in one go and thirty-two of
them were private work that merely lives in the same account.

The checks over it hold two invariants for every case: **no state is
lost and none is invented**, and **the verdict is never kinder than its
readings**. They are held on the first screen, and then again on every
screen and on the project page, because a rule measured on one screen
is a rule the other eight can break quietly. A summary on the first
screen therefore shows the **spread** of states of what it summarises,
one dot with a count per state, and never only the worst one.

## What is not there yet

- **Removing.** The console adds and changes; it never takes anything
  away. Removing a service, or a project, is `aegis org` by hand.
- **Somebody else's console.** A person who is not the operator looking
  at their own project needs Cloudflare Access and a tunnel of its own,
  and today Access admits a single email address. That is the original
  mission and it is still ahead.
- **Sizes of your own.** A service's `tamano` (chico, mediano, grande)
  is the other ceiling, inside the plan, and it is still only the three
  the seed ships. The same door would serve it.
- **Somebody who is not the operator.** See above; and until then the
  console is one person's.
