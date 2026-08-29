# teeth for check 151 (the product carries no literal credential)
#
# One red per shape the check names, and red_1 is the regression itself:
# what libexec/aegis-rotate carried until 2026-08-29 and what an
# automated scan flagged in the public repository. red_4 and red_5 are
# the same day's second lesson — the first three reds all wrote the
# token BARE, on a line of its own, and that agreement between them is
# what let a token pasted inside the syntax it belongs to pass green for
# half a day.

# an Authorization Basic with REAL base64 comes back into the tree.
#
# The base64 is BUILT here and not written out, for the reason tooth 116
# learned the hard way: whatever a tooth writes down it carries forever,
# in a directory that no sweep looks at. The plaintext behind it says
# out loud what it is.
red_1() {
    printf '\n# curl -H "Authorization: Basic %s" https://argocd.example.test/api\n' \
        "$(printf 'tooth:value-minted-by-the-tooth' | base64 -w0)" \
        >> "$AEGIS_ROOT/libexec/aegis-rotate"
}

# a Bearer token pasted whole into a note. A comment is in scope on
# purpose: a token does not stop being a token because somebody put a
# `#` in front of it, which is the same reasoning check 116 applies to
# an address in a comment.
red_2() {
    printf '\n# the note pasted the header whole: Authorization: Bearer tooth-bearer-value-minted-here\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# the third shape: a password with a literal value in an inline JSON —
# the exact spelling the ArgoCD negative tooth used to have
red_3() {
    cat >> "$AEGIS_ROOT/libexec/aegis-rotate" <<'EOF'

# the shape this file carried before the value was manufactured:
#   -d '{"username":"admin","password":"tooth-password-minted-here"}'
EOF
}

# control: documentation prose that names the header and its
# placeholder. This is the case the check MUST leave alone — it is how
# every protocol in this tree tells the reader where their own token
# goes, and a check that bit it would be switched off within a week.
control_1() {
    printf '\nAuthenticate with `Authorization: Bearer <key>`, where <key> is the token the panel issued.\n' \
        >> "$AEGIS_ROOT/docs/OPERATE.md"
}

# control: the same header in CODE, with the value interpolated — which
# is what the phases really do
control_2() {
    printf '\n# curl -H "Authorization: Bearer $CF_API_TOKEN" against the API\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# control: the seed's placeholder convention. 19 characters, no
# character the interpolation rule looks for, and not base64 either —
# it needed its own rule, and this control is what found that out.
control_3() {
    printf '\n# the template writes: Authorization: Bearer __CF_TUNNEL_TOKEN__\n' \
        >> "$AEGIS_ROOT/seed/platform/ansible/inventory/group_vars/all.yml"
}

# ── inside the syntax the token belongs to (2026-08-29) ─────────────
# The false negative these two were written for: `}` and `>` were on the
# interpolation list, so the capture that runs to the `"}` closing a JSON
# object, or to the `>` closing an HTML attribute, was read as a
# placeholder and dropped. Pasting a token inside the body it travels in
# is the most natural way for one to arrive, and it is the shape of the
# alert that started this check — the first three reds all missed it
# because they all wrote the token bare.
red_4() {
    printf '\n# the paste came in whole: {"Authorization": "Bearer tooth-bearer-inside-a-json"}\n' \
        >> "$AEGIS_ROOT/lib/common.sh"
}

# the `>` half of the same fix: an HTML attribute closes the value too
red_5() {
    printf '\n<meta name="api-auth" content="Bearer tooth-token-in-an-html-attribute">\n' \
        >> "$AEGIS_ROOT/docs/OPERATE.md"
}

