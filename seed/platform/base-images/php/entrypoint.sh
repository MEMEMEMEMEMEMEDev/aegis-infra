#!/bin/sh
# aegis-base-php — PID 1. Runs php-fpm and nginx, and DIES WHEN EITHER
# OF THEM DIES.
#
# THAT LAST SENTENCE IS THE ENTIRE POINT OF THIS FILE, so it is worth
# saying why. The obvious way to run these two in one container is
# `php-fpm -D` (daemonize) followed by `nginx -g 'daemon off;'`. It
# works, and it fails in the worst available shape: when php-fpm dies,
# nginx keeps running, the container stays Running, a readiness probe on
# a static path keeps passing, the pod is never restarted, and every
# request gets a 502 from a service Kubernetes believes is healthy. That
# is the exact family of failure the field notes keep paying for — green
# everywhere, broken where somebody is looking. So: both in the
# background, both watched, and the first one to exit takes the
# container down. Kubernetes restarts it, which is its job.
#
# ─────────────────────────────────────────────────────────────────────
# TWO THINGS IN HERE ARE NOT STYLE. Both were MEASURED on 2026-09-12
# while writing this file, and the first version got both wrong.
#
# 1 · A CHILD STARTED WITH `&` HAS SIGQUIT AND SIGINT IGNORED, and the
#     disposition SURVIVES exec. POSIX requires it of asynchronous
#     commands in a non-interactive shell; measured here as
#     `SigIgn: 0000000000000006` in /proc/<pid>/status (bit 2 = SIGINT,
#     bit 3 = SIGQUIT). `set -m` would avoid it and is NOT an option:
#     it needs a controlling terminal, which PID 1 in a container does
#     not have ("can't access tty; job control turned off").
#     nginx and php-fpm both install their own handlers at startup and
#     so normally override the inherited SIG_IGN — but the container's
#     STOPSIGNAL is SIGQUIT, so EVERY rollout depends on that being
#     true, and "normally" is not a thing to hang a rollout on. Hence
#     the escalation in parar(): QUIT first because it is the graceful
#     one, then TERM (never auto-ignored), then KILL. Bounded, so the
#     worst case is slow instead of forever.
#
# 2 · `kill -0` IS TRUE FOR A ZOMBIE. A dead child stays visible until
#     it is reaped, so a liveness check built on `kill -0` can report a
#     corpse as healthy — which is this file's one job, inverted. Some
#     shells reap async children on their own and it happens to work;
#     that is luck, not a contract. vivo() reads the state field of
#     /proc/<pid>/stat instead and treats Z as dead. (This is also how
#     the first version of the TEST for this file was wrong, and it
#     reported a hang that was really its own bug — which is exactly
#     why a guard gets watched failing before it is believed.)
# ─────────────────────────────────────────────────────────────────────
#
# NO `set -e`. This is PID 1 of a production container and the shutdown
# path is full of commands whose failure is expected and harmless
# (signalling something that just died). Under `set -e` one of those
# takes the shell out mid-shutdown, leaving the other process running.
# Every failure that matters here is checked explicitly.
#
# POSIX sh, no `wait -n`: busybox ash has had it for a while, but the
# whole value of this file is being boring and correct on whatever the
# distribution ships next.
set -u

# How long the graceful signal gets before the escalation. It is a knob
# because the right number is the pod's terminationGracePeriodSeconds
# minus a margin, and that belongs to the consumer, not to the base.
GRACIA_QUIT="${AEGIS_PARADA_GRACIA:-10}"
GRACIA_TERM=5

log() { echo "[aegis-php] $*" >&2; }

# True only if the process EXISTS and is not a zombie. See note 2 above.
# The state is the first field after the last ')', because a process
# name can itself contain spaces and parentheses.
vivo() {
    [ -r "/proc/$1/stat" ] || return 1
    _estado=$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)
    [ -n "$_estado" ] || return 1
    [ "$_estado" != "Z" ]
}

esperar_muerte() {        # <pid> <segundos>  → 0 si murió, 1 si aguantó
    _n=0
    while vivo "$1"; do
        _n=$((_n + 1))
        if [ "$_n" -gt "$2" ]; then return 1; fi
        sleep 1
    done
    return 0
}

parar() {                 # <pid> <nombre>
    if ! vivo "$1"; then return 0; fi
    kill -QUIT "$1" 2>/dev/null
    if esperar_muerte "$1" "$GRACIA_QUIT"; then return 0; fi
    log "$2 did not stop on SIGQUIT after ${GRACIA_QUIT}s — escalating to SIGTERM (see note 1 at the top)"
    kill -TERM "$1" 2>/dev/null
    if esperar_muerte "$1" "$GRACIA_TERM"; then return 0; fi
    log "$2 still alive — SIGKILL"
    kill -KILL "$1" 2>/dev/null
    esperar_muerte "$1" 5
    return 0
}

# nginx's temp paths live in /tmp (see nginx.conf) because the root
# filesystem is read-only. nginx creates most of them on first use, but
# client_body_temp is only reached by a request with a body big enough
# to spill — i.e. the first product image somebody uploads, in
# production, weeks later. Creating them here costs nothing and removes
# the whole class.
mkdir -p /tmp/client_temp /tmp/proxy_temp_path /tmp/fastcgi_temp \
         /tmp/uwsgi_temp /tmp/scgi_temp || {
    log "FATAL: cannot write /tmp — the pod needs an emptyDir mounted there"
    exit 1
}

# OPTIONAL PRE-START HOOK, and its optionality is a boundary: a base
# image has no business deciding whether an application runs its
# migrations at boot. If the consumer ships an executable at this path
# it runs to completion BEFORE anything listens, and a non-zero exit
# stops the container — a pod that cannot migrate must not serve.
if [ -x /app/bin/pre-start ]; then
    log "running /app/bin/pre-start"
    if ! /app/bin/pre-start; then
        log "FATAL: /app/bin/pre-start failed; not starting the servers"
        exit 1
    fi
    log "pre-start finished"
fi

FPM_PID=""
NGINX_PID=""

detener() {
    log "signal received — stopping nginx and php-fpm"
    [ -n "$NGINX_PID" ] && parar "$NGINX_PID" nginx
    [ -n "$FPM_PID" ] && parar "$FPM_PID" php-fpm
    exit 0
}
trap detener TERM QUIT INT

# php-fpm FIRST: nginx answers on 8080 and the readiness probe follows
# right behind it, so starting the thing that renders pages before the
# thing that accepts connections avoids a window of 502s on every
# rollout.
log "starting php-fpm"
php-fpm84 --nodaemonize --fpm-config /etc/php84/php-fpm.conf &
FPM_PID=$!

log "starting nginx"
nginx -g 'daemon off;' &
NGINX_PID=$!

log "php-fpm pid $FPM_PID, nginx pid $NGINX_PID — watching both"

while :; do
    if ! vivo "$FPM_PID"; then
        wait "$FPM_PID" 2>/dev/null
        log "php-fpm (pid $FPM_PID) exited — taking the container down so it gets restarted"
        parar "$NGINX_PID" nginx
        exit 1
    fi
    if ! vivo "$NGINX_PID"; then
        wait "$NGINX_PID" 2>/dev/null
        log "nginx (pid $NGINX_PID) exited — taking the container down so it gets restarted"
        parar "$FPM_PID" php-fpm
        exit 1
    fi
    sleep 1
done
