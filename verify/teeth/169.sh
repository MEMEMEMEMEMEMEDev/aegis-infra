# teeth of check 169 — the transient-network list speaks every language
# the seed downloads in.

# THE STATE THE ARTIFACT WAS IN until 2026-09-01: every signature came
# from Go and git, and the longest build in the product downloads with
# pip. A read timeout against files.pythonhosted.org was reported as
# «a real failure, it is not retried» and stopped a four-hour build.
red_1() {
    sed -i "s/|ReadTimeoutError//; s/|Read timed out//; s/|IncompleteRead//" \
        "$AEGIS_ROOT/lib/common.sh"
}

# the same hole for the tool every application front-end builds with.
red_2() {
    sed -i "s/|ETIMEDOUT//; s/|ECONNRESET//; s/|ENOTFOUND//; s/|network timeout//" \
        "$AEGIS_ROOT/lib/common.sh"
}

# and for the one the platform's own bases use.
red_3() {
    sed -i "s/|temporary error//" "$AEGIS_ROOT/lib/common.sh"
}

# the list gone altogether: nothing can tell a hiccup from a defect,
# and this check has to say so rather than skip.
red_4() {
    sed -i "s/^AEGIS_NET_SIGS=/AEGIS_NET_FIRMAS=/" "$AEGIS_ROOT/lib/common.sh"
}

# a new downloader arrives in the seed and nobody teaches the retry
# its language — the shape of the original bug, repeated.
red_5() {
    mkdir -p "$AEGIS_ROOT/seed/platform/ai/engine-nuevo"
    printf 'FROM __FROM_PYTHON__\nRUN go install example.com/x@latest\n' \
        > "$AEGIS_ROOT/seed/platform/ai/engine-nuevo/Containerfile"
    # `dial tcp` opens the list, with no pipe before it: the first
    # version of this tooth tried to strip «|dial tcp» and removed
    # nothing, so the mutation was inert and the tooth did not bite.
    sed -i "s/dial tcp|//; s/|failed to get git//" "$AEGIS_ROOT/lib/common.sh"
}

# control: the paragraph explaining the provenance of each signature
# names the tools and their messages. Reading it as the list itself is
# the trap corrected in 161, 163, 165, 166, 167 and 168.
control_1() {
    printf '\n# note: pip says ReadTimeoutError and npm says ETIMEDOUT.\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: a Containerfile that downloads nothing adds no obligation.
control_2() {
    mkdir -p "$AEGIS_ROOT/seed/platform/ai/engine-quieto"
    printf 'FROM __FROM_PYTHON__\nCMD ["python","-c","print(1)"]\n' \
        > "$AEGIS_ROOT/seed/platform/ai/engine-quieto/Containerfile"
}
