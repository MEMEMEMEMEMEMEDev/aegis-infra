"""Who is allowed to ask this console for something, and who is allowed
to make it write.

WHY THIS IS A MODULE AND NOT FOUR `if`s IN THE HANDLER. Every rule here
is a sentence about an attack that does not look like one from inside
the server: the request arrives well-formed, over the loopback
interface, from a process on this machine, and the operator is sitting
in front of the browser that sent it. There is nothing to notice at
runtime. So the rules are written where they can be EXERCISED — a pure
function, a table of hostile requests, and a check that runs them.

THE TWO HOLES, and the first one is already open on a console that only
reads:

  · DNS REBINDING. `evil.test` resolves to a real address, the page
    loads, and a moment later the same name resolves to 127.0.0.1. The
    browser keeps the page's origin —it is still `evil.test`— and its
    fetches now land here. Same-origin policy is not violated: the
    origin genuinely did not change. The only thing that gives it away
    is the `Host` header, which carries the name the browser dialled and
    not the address it reached. A console that answers to any Host hands
    a stranger everything the round can see about this instance.

  · CSRF. Cross-origin form submissions are not blocked by same-origin
    policy — they never were. Any page the operator visits can POST here
    with a body of its choosing. The defence is not secrecy of the URL
    (it is 127.0.0.1 and a port) but a token the attacking page cannot
    READ: it can send a request, it cannot see the response, so it
    cannot learn what to send.

WHAT IS DELIBERATELY NOT HERE: a password. This is not authentication
and it does not pretend to be. Anything already running as this user can
read the age key and the kubeconfig directly and has no need of a
console. What these rules stop is a REMOTE page borrowing the operator's
browser as a way in, which is a different and entirely real thing.
"""
import hmac

# The names a loopback server may legitimately be called by. A name that
# is not one of these arrived from somewhere that had to be TOLD about
# this port, which on 127.0.0.1 means it was not a local navigation.
LOOPBACK_NAMES = ("127.0.0.1", "localhost", "[::1]", "::1")


def allowed_hosts(port):
    return {f"{name}:{port}" for name in LOOPBACK_NAMES} | set(LOOPBACK_NAMES)


def _header(headers, name):
    """Headers are case-insensitive and may be absent. Written once so
    that no rule below accidentally reads a header that is spelled
    differently by the client that matters."""
    if headers is None:
        return None
    get = getattr(headers, "get", None)
    if get is None:
        return None
    value = get(name)
    if value is None:
        value = get(name.lower())
    return value.strip() if isinstance(value, str) else value


def why_not_read(headers, port):
    """The reason this request may not be answered at all, or None.

    It applies to GET as much as to POST: the read-only console shows
    every hostname, every organization, every finding of the round. That
    is not a small thing to hand over.
    """
    host = _header(headers, "Host")
    if not host:
        return ("the request carries no Host header: a loopback console cannot tell "
                "who it is being called by")
    if host.lower() not in allowed_hosts(port):
        return (f"the request was addressed to {host!r} and this console answers only to "
                f"the loopback names: a name that resolves here from somewhere else is "
                f"how a page on the internet reaches a server on your machine")
    return None


def why_not_write(method, headers, token, sent):
    """The reason this request may not CHANGE anything, or None.

    `token` is the one this process minted when it started; `sent` is
    what the request carried. Read `why_not_read` first: this answers a
    narrower question and assumes that one already said yes.
    """
    if method != "POST":
        # A change that can be made with a GET can be made by an image
        # tag, a link somebody sends, or a preloader. The method is not
        # a formality.
        return (f"a {method} may not change anything: what a GET can do, a link in "
                f"somebody else's page can do")

    origin = _header(headers, "Origin")
    if not origin:
        # Browsers send Origin on cross-origin POSTs and on same-origin
        # ones. Its absence means the request did not come from the
        # page, and the page is the only thing meant to write here.
        return ("the request carries no Origin: this console writes what its own page "
                "submits, and nothing else")
    host = _header(headers, "Host") or ""
    if origin.lower() not in (f"http://{host.lower()}",):
        return (f"the request comes from {origin!r} and this console only accepts what "
                f"its own page submits: a form on another site can post here, and the "
                f"browser will send it")

    site = _header(headers, "Sec-Fetch-Site")
    if site is not None and site.lower() != "same-origin":
        return (f"the browser says this navigation came from {site!r} and not from this "
                f"page")

    if not token:
        # The server has no token to compare against. Refusing is the
        # only honest answer: accepting would mean the defence silently
        # does not exist.
        return ("this console has no token of its own, so it cannot tell its own form "
                "from anybody else's")
    if not sent or not hmac.compare_digest(str(sent), str(token)):
        return ("the form did not carry this console's token: a page on another site can "
                "send a request here, but it cannot read the answer, so it never learns "
                "what the token is")
    return None
