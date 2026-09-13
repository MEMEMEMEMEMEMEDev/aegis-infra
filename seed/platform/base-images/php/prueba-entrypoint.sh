#!/bin/sh
# aegis-base-php — the guard for entrypoint.sh.
#
# WHY IT EXISTS. entrypoint.sh has one job: take the container down when
# either of its two processes dies. Nothing in the image build can
# assert that — no `--version` call proves a supervisor supervises — and
# the failure it prevents is invisible (a pod Running while nginx serves
# 502). So the supervisor gets a test, and the test runs against
# `busybox ash`, which is the shell the image actually has.
#
# It replaces php-fpm84 and nginx with fakes it controls, so it runs
# anywhere: no container runtime, no cluster, about twenty seconds.
#
#   sh base-images/php/prueba-entrypoint.sh
#
# TO SEE IT FAIL (which is the only way to know it works), break
# entrypoint.sh on purpose — swap the `exit 1` in the watch loop for
# `sleep 1`, or drop the escalation in parar() — and run it again.
set -u

AQUI=$(cd "$(dirname "$0")" && pwd)
EP="$AQUI/entrypoint.sh"
SH=${SH_PRUEBA:-sh}
TRABAJO=$(mktemp -d)
trap 'pkill -f "$TRABAJO/bin/" 2>/dev/null; rm -rf "$TRABAJO"' EXIT INT TERM

mkdir -p "$TRABAJO/bin" "$TRABAJO/tmp"
fallos=0
casos=0

# The entrypoint writes to /tmp and looks for /app/bin/pre-start; both
# are redirected into the sandbox so the test touches nothing real.
sed -e "s#/tmp/client_temp /tmp/proxy_temp_path /tmp/fastcgi_temp #$TRABAJO/tmp/a $TRABAJO/tmp/b $TRABAJO/tmp/c #" \
    -e "s#/tmp/uwsgi_temp /tmp/scgi_temp#$TRABAJO/tmp/d $TRABAJO/tmp/e#" \
    -e "s#/app/bin/pre-start#$TRABAJO/pre-start#g" \
    "$EP" > "$TRABAJO/entrypoint.sh"
chmod +x "$TRABAJO/entrypoint.sh"

# Two fakes, IN PYTHON AND NOT IN SHELL, and that is not a preference.
# A shell cannot re-handle a signal it inherited as ignored (POSIX), and
# every child started with `&` inherits SIGQUIT ignored — see note 1 in
# entrypoint.sh. So a shell fake is ALWAYS deaf to SIGQUIT and there is
# no way to model the obedient case with one. nginx and php-fpm are C
# programs that call sigaction() directly, which does override an
# inherited SIG_IGN; python's signal.signal() does the same, so these
# fakes behave the way the real binaries do.
#
#   obediente  honours SIGQUIT, like nginx and php-fpm
#   sordo      ignores it, which is what the escalation in parar()
#              exists for and the only way to prove that path runs
crear_falso() {           # <nombre> <obediente|sordo>
    if [ "$2" = obediente ]; then
        _quit='signal.signal(signal.SIGQUIT, lambda *_: sys.exit(0))'
    else
        _quit='signal.signal(signal.SIGQUIT, signal.SIG_IGN)'
    fi
    cat > "$TRABAJO/bin/$1" <<EOF
#!/usr/bin/env python3
import signal, sys, time
$_quit
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
while True:
    time.sleep(1)
EOF
    chmod +x "$TRABAJO/bin/$1"
}

arrancar() {              # deja $EP_PID
    AEGIS_PARADA_GRACIA=2 PATH="$TRABAJO/bin:$PATH" \
        $SH "$TRABAJO/entrypoint.sh" > "$TRABAJO/salida.log" 2>&1 &
    EP_PID=$!
    sleep 2
}

# Waits for the entrypoint with a hard ceiling, so a hang is reported as
# a failure instead of hanging the test too. It leaves the answer in $RC
# and does NOT print it, because the caller would then need a command
# substitution — and `wait` inside a subshell cannot wait for a process
# that belongs to the parent shell: it returns 127 and every case looks
# broken. (That was this test's first bug, and it accused entrypoint.sh
# of a hang that was entirely its own.)
esperar_fin() {           # <segundos> → deja el código en $RC, o 'COLGADO'
    ( sleep "$1"; kill -KILL "$EP_PID" 2>/dev/null ) & perro=$!
    wait "$EP_PID"; RC=$?
    kill "$perro" 2>/dev/null; wait "$perro" 2>/dev/null
    if [ "$RC" = 137 ]; then RC=COLGADO; fi
}

comprobar() {             # <descripción> <obtenido> <esperado>
    casos=$((casos + 1))
    if [ "$2" = "$3" ]; then
        printf '  ok    %s\n' "$1"
    else
        printf '  FALLA %s  (obtenido: %s, esperado: %s)\n' "$1" "$2" "$3"
        fallos=$((fallos + 1))
    fi
}

limpiar() { pkill -f "$TRABAJO/bin/" 2>/dev/null; sleep 1; }

echo "prueba-entrypoint  (shell: $SH)"

# ── 1 · php-fpm muere → el contenedor cae ───────────────────────────
crear_falso php-fpm84 obediente; crear_falso nginx obediente
arrancar
kill -KILL "$(pgrep -f "$TRABAJO/bin/php-fpm84" | head -1)" 2>/dev/null
esperar_fin 20
comprobar "php-fpm muere → el entrypoint sale con 1" "$RC" 1
comprobar "  y nginx no queda huérfano" "$(pgrep -cf "$TRABAJO/bin/nginx")" 0
limpiar

# ── 2 · nginx muere → el contenedor cae ─────────────────────────────
arrancar
kill -KILL "$(pgrep -f "$TRABAJO/bin/nginx" | head -1)" 2>/dev/null
esperar_fin 20
comprobar "nginx muere → el entrypoint sale con 1" "$RC" 1
comprobar "  y php-fpm no queda huérfano" "$(pgrep -cf "$TRABAJO/bin/php-fpm84")" 0
limpiar

# ── 3 · una señal de parada a PID 1 → parada ordenada ───────────────
# SIGTERM y no SIGQUIT, y la razón es la MISMA que entrypoint.sh
# documenta en su nota 1: este test arranca el entrypoint con `&`, así
# que el entrypoint TAMBIÉN hereda SIGQUIT ignorada y no hay forma de
# entregársela desde acá. En el contenedor real PID 1 lo arranca el
# runtime, no una shell, y sí la recibe. El camino de código es el
# mismo —`trap detener TERM QUIT INT`—, así que lo que falta por cubrir
# no es nuestro código sino que la señal llegue: eso se comprueba en el
# pod vivo, y está en la lista de verificación.
arrancar
kill -TERM "$EP_PID" 2>/dev/null
esperar_fin 20
comprobar "señal de parada a PID 1 → sale con 0" "$RC" 0
comprobar "  sin procesos vivos" "$(pgrep -cf "$TRABAJO/bin/")" 0
limpiar

# ── 4 · un proceso SORDO a SIGQUIT igual se para ────────────────────
# Ésta es la que justifica la escalada. Sin ella el entrypoint se
# quedaba esperando para siempre a algo que nunca iba a morir.
crear_falso nginx sordo
arrancar
kill -TERM "$EP_PID" 2>/dev/null
esperar_fin 25
comprobar "nginx sordo a SIGQUIT → igual sale con 0" "$RC" 0
comprobar "  la escalada quedó registrada" \
    "$(grep -c 'did not stop on SIGQUIT' "$TRABAJO/salida.log")" 1
comprobar "  sin procesos vivos" "$(pgrep -cf "$TRABAJO/bin/")" 0
limpiar
crear_falso nginx obediente

# ── 5 · pre-start que falla → no se arranca nada ────────────────────
printf '#!/bin/sh\nexit 3\n' > "$TRABAJO/pre-start"; chmod +x "$TRABAJO/pre-start"
arrancar
esperar_fin 20
comprobar "pre-start falla → sale con 1" "$RC" 1
comprobar "  y no arrancó ningún servidor" "$(pgrep -cf "$TRABAJO/bin/")" 0
rm -f "$TRABAJO/pre-start"
limpiar

echo
if [ "$fallos" -eq 0 ]; then
    echo "$casos casos, todos bien"
    exit 0
fi
echo "$casos casos, $fallos FALLAN"
exit 1
