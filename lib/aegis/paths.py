"""Where everything lives — the python half of lib/paths.sh.

Both decide the same thing and read the SAME environment variables, so
a bash command and a python one sitting side by side cannot disagree
about where the instance is. If they ever do, it is a single class of
bug and it gets fixed in two files, not twenty.

  AEGIS_ROOT   the PRODUCT: bin/ libexec/ lib/ init/ verify/ seed/
  AEGIS_HOME   the INSTANCE: platform/ .init-state/ .state-secrets/
               .age-public aegis.conf

The bug this closes, found on 2026-08-23 while moving the code:
`aegis-org` computed its root as `dirname(dirname(__file__))`. It lived
in <instance>/platform/bin/, so that gave <instance>/platform and it
worked. Once it moved to <product>/libexec/ the same line kept
compiling and started pointing at the PRODUCT — looking for orgs/ and
k8s/ where they are not. No tool would have warned: it is C1/C2's
"dependency invisible to a grep", with a date on it.
"""
import os
import pathlib


def aegis_root() -> pathlib.Path:
    """The product. From the variable if there is one; otherwise from
    this file (lib/aegis/paths.py -> two levels up)."""
    v = os.environ.get("AEGIS_ROOT")
    if v:
        return pathlib.Path(v)
    return pathlib.Path(__file__).resolve().parent.parent.parent


def aegis_home() -> pathlib.Path:
    """The instance. Same rule as lib/paths.sh, in the same order."""
    v = os.environ.get("AEGIS_HOME")
    if v:
        return pathlib.Path(v)
    root = aegis_root()
    # compatibility with the v2 shape: if the product has a platform/
    # beside it, that is the instance (which is how the house machine
    # still is today).
    if (root / "platform").is_dir():
        return root
    return pathlib.Path.home() / "aegis"


def platform_dir() -> pathlib.Path:
    """The live checkout of the platform repo. This is what v2 called
    RAIZ inside aegis-org."""
    return pathlib.Path(os.environ.get("PLATFORM_DIR") or (aegis_home() / "platform"))


def orgs_dir() -> pathlib.Path:
    return platform_dir() / "orgs"


def state_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AEGIS_STATE_DIR") or (aegis_home() / ".init-state"))


def secrets_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AEGIS_SECRETS_DIR") or (aegis_home() / ".state-secrets"))


def conf() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AEGIS_CONF") or (aegis_home() / "aegis.conf"))


def read_conf() -> dict:
    """The wizard's aegis.conf, as a dictionary.

    It is a file of bash assignments (KEY=value). It is READ, never
    executed: a config file should not be able to run commands, and in
    v2 every python command that needed it parsed it its own way."""
    d = {}
    p = conf()
    if not p.is_file():
        return d
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k = k.strip()
        if not k.replace("_", "").isalnum():
            continue
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        d[k] = v
    return d
