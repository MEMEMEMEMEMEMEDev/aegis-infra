# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use
GitHub's private vulnerability reporting on this repository
(*Security → Report a vulnerability*); it reaches the maintainer and
nobody else.

Include what you can reproduce: the command, the phase or the check
involved, and what the instance looked like. You will get an answer
in the advisory itself.

## What is in scope

- The product: everything under `bin/ libexec/ lib/ init/ verify/ seed/`.
- The way the init handles secrets: the age key, the encrypted store,
  the credentials it generates, what it prints and what it never
  prints.
- The supply chain the seed installs: the mirror, the scanner, the
  signature and its admission policy.

## What is not

- The instance you deploy from it (that is yours), and the
  third-party components it installs (report those upstream; if the
  seed pins a vulnerable version, that *is* in scope — say so).

## How the product treats secrets

The rules are written down and enforced: secrets never travel in
argv, are never printed, and are encrypted at the path they live in.
`seed/platform/docs/conventions/secrets.md` is the reference;
`docs/AGENTS.md` §4 is the operational form of it.
