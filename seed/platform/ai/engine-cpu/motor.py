"""engine-cpu — the AI lane that does NOT touch the GPU.

Four capabilities that are not an LLM and therefore do not go through
the gateway's engine lanes: synthesising speech, transcribing it,
detecting objects, and embedding text.

WHY CPU AND NOT GPU, the decision that governs this whole file: behind
this there is ONE card, and the LLM lanes live on it with their KV
cache. The models here fit in CPU with room to spare — the largest is
82 million parameters — and putting them on the card would compete for
VRAM with the only thing that actually needs it. The desktop keeps its
share too, which was the whole problem the first time around.

WHAT THIS FILE IS NOT ABOUT: signature, NetworkPolicy, tenant quota and
budgets are imposed from OUTSIDE — by the Deployment, by the admission
policy and by the gateway in front. The module says out loud at start-up
which of the two worlds it is in, so nobody confuses a local run with
the deployed lane.

A NOTE ON THE WIRE, and it is deliberate: the JSON keys and the error
codes below are in Spanish. They are the contract a tenant's frontend
already consumes, and translating them is a breaking change to a live
integration — a decision for the operator, not a side effect of moving
this file into the product. The prose is English; the contract was left
alone, and this paragraph is the declaration rather than the silence.
"""

from __future__ import annotations

import io
import logging
import os
import time
import wave
from contextlib import asynccontextmanager
from dataclasses import dataclass
from functools import partial
from pathlib import Path

import anyio
import numpy as np
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field

log = logging.getLogger("engine-cpu")

MODELOS = Path(
    os.environ.get("AEGIS_MODELOS_CPU")
    or Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "aegis/modelos-cpu"
)

# Threads per WORKER (not per engine: see OBREROS below). Without this
# number, onnxruntime and CTranslate2 grab every core they can see, and
# since the engines live in the same process they end up fighting each
# other: more threads, more contention, and LESS work done.
#
# Four and not eight, and that changed when it was measured: going from
# 8 to 16 threads per worker left the time per request THE SAME (2.15 ->
# 2.17 s). Whisper saturates well before eight — the bottleneck is
# memory bandwidth, not arithmetic — so the extra threads were not
# speeding anything up, they were merely reserved. Spreading them across
# more workers does help.
#
# And they are PER ENGINE, because the three do not behave alike:
# Whisper saturates at four threads, but RT-DETR and Kokoro do use more
# (dropping vision from 8 to 4 cost it 75% of its time: 0.12 -> 0.21 s).
#
# The budget comes out like this, over 32 threads:
#   oido    4 workers x 4 = 16
#   voz     2 workers x 6 = 12
#   vision  2 workers x 6 = 12
# That is 40 at the theoretical peak, and on purpose: they are CAPS, not
# reservations. All three saturated at once is a case that does not
# happen — a visitor uses one program at a time — and measured, the
# three together get in each other's way by ~40%, which is the real
# ceiling. Splitting exactly 32 would leave every engine slow in the
# normal case, which is the one that always happens.
HILOS = {
    "voz": int(os.environ.get("AEGIS_HILOS_VOZ", "6")),
    "oido": int(os.environ.get("AEGIS_HILOS_OIDO", "4")),
    "vision": int(os.environ.get("AEGIS_HILOS_VISION", "6")),
    "vector": int(os.environ.get("AEGIS_HILOS_VECTOR", "4")),
}

# HOW MANY REQUESTS EACH ENGINE SERVES AT ONCE.
#
# It used to be one and that was that: a lock per engine, and the second
# arrival waited for the whole of the first. For vision and voice that
# is fine — they take 0.12 s and 0.40 s, and whoever waits does not
# notice — but not for hearing: a transcription is ~2.5 s, and with
# eight people the last one waited 18.
#
# MEASURED (28 s of audio, eight requests at once):
#
#   threads×workers  alone   throughput  p95      worst case
#      8 × 1        2.15s     0.46/s   18.27s      3.11s
#     16 × 1        2.17s     0.48/s   17.24s      3.00s   <- twice the
#      4 × 2        2.51s     0.58/s   13.93s      3.66s      threads
#      4 × 4        2.50s     0.63/s   12.68s      3.72s      buys NOTHING
#      2 × 8        3.61s     0.67/s   11.97s      5.34s
#
# Both lessons are in that table. The first: going from 8 to 16 threads
# leaves the time THE SAME — Whisper saturates much earlier, the
# bottleneck is memory and not arithmetic — so the extra threads were
# wasted. The second: spreading them across more workers does buy
# throughput, up to +46%.
#
# And why 4×4 and not 2×8, which gives more throughput: because whoever
# arrives ALONE pays 3.61 s instead of 2.50. The normal case for a
# single-visitor site is one person looking, and optimising for the
# crowd would charge the common case 44%. 4×4 keeps almost all the
# throughput (0.63 of 0.67) while paying 16%.
OBREROS = {
    "voz": int(os.environ.get("AEGIS_OBREROS_VOZ", "2")),
    "oido": int(os.environ.get("AEGIS_OBREROS_OIDO", "4")),
    "vision": int(os.environ.get("AEGIS_OBREROS_VISION", "2")),
    "vector": int(os.environ.get("AEGIS_OBREROS_VECTOR", "2")),
}

WHISPER = os.environ.get("AEGIS_WHISPER", "small")

# ── Input caps ───────────────────────────────────────────────────────
# They are validated BEFORE a decoder touches the file. A .webm or a
# .png are formats with complex parsers written in C, and they are the
# classic attack surface of a service that accepts uploads: the cheap
# defence is not to let in what we are not going to be able to use.
MAX_TEXTO_VOZ = 300      # the same cap the translation lane uses, for coherence
MAX_AUDIO_BYTES = 8 * 1024 * 1024
MAX_AUDIO_SEG = 30
MAX_IMAGEN_BYTES = 6 * 1024 * 1024

# File signatures. The check is by CONTENT and not by the extension nor
# by the Content-Type: the client writes both, and neither of them is a
# statement about what the file is.
FIRMAS_AUDIO = {
    b"\x1a\x45\xdf\xa3": "webm",   # Matroska/WebM — what the browser records
    b"OggS": "ogg",
    b"RIFF": "wav",                # confirmed further down with 'WAVE'
    b"ID3": "mp3",
    b"fLaC": "flac",
}
FIRMAS_IMAGEN = {
    b"\xff\xd8\xff": "jpeg",
    b"\x89PNG\r\n\x1a\n": "png",
    b"RIFF": "webp",               # confirmed further down with 'WEBP'
}


def _mira(datos: bytes, firmas: dict[bytes, str]) -> str | None:
    for magia, nombre in firmas.items():
        if datos.startswith(magia):
            return nombre
    # MP4/M4A does not start with its signature: 'ftyp' sits at byte 4.
    if len(datos) > 11 and datos[4:8] == b"ftyp" and firmas is FIRMAS_AUDIO:
        return "mp4"
    # MP3 with no ID3 tag: frame sync.
    if firmas is FIRMAS_AUDIO and len(datos) > 1 and datos[0] == 0xFF and datos[1] & 0xE0 == 0xE0:
        return "mp3"
    return None


def formato_audio(datos: bytes) -> str:
    f = _mira(datos, FIRMAS_AUDIO)
    if f == "wav" and datos[8:12] != b"WAVE":
        f = None
    if f is None:
        raise HTTPException(415, detail={
            "error": "formato",
            "mensaje": "Ese archivo no parece audio que el programa sepa abrir.",
        })
    return f


def formato_imagen(datos: bytes) -> str:
    f = _mira(datos, FIRMAS_IMAGEN)
    if f == "webp" and datos[8:12] != b"WEBP":
        f = None
    if f is None:
        raise HTTPException(415, detail={
            "error": "formato",
            "mensaje": "Ese archivo no parece una imagen JPEG, PNG o WebP.",
        })
    return f


async def leer_acotado(subido: UploadFile, tope: int) -> bytes:
    """Read the body cutting off at `tope`, WITHOUT materialising the rest.

    A bare `await subido.read()` would read the whole file into memory
    and only then would we measure: by that point the damage of a
    one-gigabyte upload is already done. Here it is read in chunks and
    aborted on overflow.
    """
    trozos, total = [], 0
    while trozo := await subido.read(64 * 1024):
        total += len(trozo)
        if total > tope:
            raise HTTPException(413, detail={
                "error": "grande",
                "mensaje": f"El archivo pasa de {tope // (1024 * 1024)} MB.",
            })
        trozos.append(trozo)
    if total == 0:
        raise HTTPException(400, detail={"error": "vacio", "mensaje": "No llegó ningún archivo."})
    return b"".join(trozos)


# ─────────────────────────────────────────────────────────────────────
# The engines
#
# Each one is loaded ONCE at start-up and stays in memory. The
# alternative — loading on the first request — turns the first visit of
# the day into twenty seconds of unexplained waiting, and the service
# would look broken exactly when somebody looks at it for the first
# time.
#
# And each one carries a LIMITER with as many seats as it has workers:
# the waiting happens at the door and not inside the model. Letting in
# more requests than there are workers would not make them go faster —
# they would go equally slowly while treading on each other — and on top
# of that the waiting would stop being visible.
#
# IT IS AN ANYIO CapacityLimiter AND NOT A threading Lock, and that
# difference is what made the first version of the pool NOT WORK. The
# work of these engines is blocking; if it runs inside a coroutine it
# blocks the entire event loop and everything serialises underneath
# whatever the semaphore does. Measured: with `async def` and a
# Semaphore of 4 seats, throughput was 0.38/s with one request, with
# four, with eight and with sixteen at once. Identical. The semaphore
# was correctly placed and protected nothing, because there were never
# two things at once to protect.
#
# The anyio limiter, on the other hand, is handed to `to_thread.run_sync`:
# the work leaves for a real thread and the waiting happens in the loop,
# which is free. The two symptoms are identical from outside — a queue
# that advances — and that is why one has to measure throughput instead
# of reading the code.
# ─────────────────────────────────────────────────────────────────────


@dataclass
class Motor:
    nombre: str
    puestos: int = 1
    # The TYPICAL cost of a request, in seconds. It starts at the
    # measured value and then MEASURES ITSELF (a moving average over
    # what each request actually took): it is the number that turns
    # "there are N in the queue" into "about X seconds", and a number
    # that measures itself does not go stale when the model or the
    # machine changes.
    costo: float = 1.0
    obj: object | None = None
    error: str | None = None
    # Created at start-up and not here: anyio wants a running loop.
    limite: anyio.CapacityLimiter | None = None
    # How many are waiting for a turn NOW. Only the event loop mutates
    # it, so it carries no lock.
    en_fila: int = 0

    # THE WAITING ROOM IS BOUNDED. With no cap the queue grows without a
    # floor and nobody knows the last arrival's wait: accepting blindly
    # is promising what you do not know. Two waiting requests per worker
    # means the worst admitted one waits ~2 typical costs — for hearing
    # that is ~5 s, which is the most a demo can ask for without an
    # explanation. Everyone else gets an honest 429 with a Retry-After
    # computed from MEASURED costs.
    @property
    def sala(self) -> int:
        return self.puestos * 2

    @property
    def espera_estimada(self) -> float:
        """How long a request entering NOW would wait, in seconds."""
        return (self.en_fila + 1) * self.costo / self.puestos

    @property
    def listo(self) -> bool:
        return self.obj is not None

    def exigir(self):
        if self.obj is None:
            # 503 and not 500: the engine is not broken, it is absent.
            # The difference matters on the browser's side, which says
            # "at rest" for a 503 and would say "something broke" for a
            # 500.
            raise HTTPException(503, detail={
                "error": "dormido",
                "mensaje": f"{self.nombre} no está disponible en este servidor.",
                "detalle": self.error or "no cargado",
            })
        return self.obj


# The initial costs are the ones MEASURED on the reference machine
# (2026-08-16); the moving average corrects them by itself from the
# first real request onwards.
voz = Motor("voz", OBREROS["voz"], costo=0.45)
oido = Motor("oido", OBREROS["oido"], costo=2.7)
vision = Motor("vision", OBREROS["vision"], costo=0.16)
# Embeddings is the one capability here that is not driven by a person
# looking at a page: other services consume it through the gateway for
# semantic search.
vector = Motor("vector", OBREROS["vector"], costo=0.05)

# The COCO classes, which come out of the model's config.json. Filled in
# on load; empty means it could not be read and the boxes would come out
# numbered, something we prefer to catch at start-up and not in the
# output.
CLASES: dict[int, str] = {}


async def en_obrero(m: Motor, trabajo):
    """Run `trabajo` on one of the engine's workers, waiting for a turn if needed.

    IT IS THE PIECE THAT MAKES THE POOL EXIST. `to_thread.run_sync`
    takes the blocking work out of the event loop — without it, a
    coroutine calling Whisper freezes the whole process for as long as
    it lasts — and the `limiter` is what imposes how many run at once.

    Both are needed together: with no thread there is no parallelism
    even with seats to spare, and with no limiter everybody comes in and
    treads on each other.

    AND THE DOOR COMES BEFORE THE QUEUE: with the room full it refuses
    instantly, with the estimated wait, instead of letting a queue grow
    whose promise nobody knows. The limiter is acquired here, separately
    from the thread, so those waiting can be counted — with `limiter=`
    inside run_sync, "waiting for a turn" and "working" are
    indistinguishable from outside.
    """
    if m.en_fila >= m.sala:
        espera = max(1, round(m.espera_estimada))
        raise HTTPException(
            429,
            detail={
                "error": "lleno",
                "mensaje": (
                    f"{m.nombre} está atendiendo a {m.puestos + m.en_fila} personas; "
                    f"probá de nuevo en unos {espera} segundos."
                ),
            },
            headers={"Retry-After": str(espera)},
        )

    m.en_fila += 1
    try:
        await m.limite.acquire()
    finally:
        m.en_fila -= 1

    t0 = time.monotonic()
    try:
        return await anyio.to_thread.run_sync(trabajo)
    finally:
        m.limite.release()
        # Moving average (80/20): it follows the real cost without
        # startling at one odd request. It is updated when the work
        # raises too — a rejection by duration also kept the worker busy
        # for a while, and that while is information.
        m.costo = 0.8 * m.costo + 0.2 * (time.monotonic() - t0)


def _sesion_onnx(ruta: Path, hilos: int):
    import onnxruntime as ort

    opciones = ort.SessionOptions()
    opciones.intra_op_num_threads = hilos
    opciones.inter_op_num_threads = 1
    opciones.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    # CPUExecutionProvider EXPLICIT. onnxruntime picks on its own, and
    # if some day somebody installs onnxruntime-gpu in this venv, this
    # service would move to the card without warning and eat the VRAM of
    # the lane that actually needs it.
    return ort.InferenceSession(str(ruta), opciones, providers=["CPUExecutionProvider"])


def cargar_voz() -> None:
    from kokoro_onnx import Kokoro

    modelo = MODELOS / "kokoro/kokoro-v1.0.onnx"
    voces = MODELOS / "kokoro/voices-v1.0.bin"
    if not modelo.exists() or not voces.exists():
        raise FileNotFoundError("faltan los pesos de Kokoro — correr `aegis ai models`")
    # Kokoro is built from an already-configured session, and not from
    # the path: it is the only way to impose the thread cap on it. With
    # `Kokoro(path, voices)` the library builds the session by itself and
    # takes every core.
    voz.obj = Kokoro.from_session(_sesion_onnx(modelo, HILOS["voz"]), str(voces))


def cargar_oido() -> None:
    from faster_whisper import WhisperModel

    # int8 on CPU is not a concession: CTranslate2 quantises to integers
    # and comes out between two and four times faster than float32, with
    # a loss that short dictation does not show. It is the mode it was
    # built for.
    #
    # `num_workers` is the right primitive for the pool: it runs N real
    # transcriptions in parallel SHARING the weights. They are not N
    # models in RAM — that would cost half a gigabyte per worker — but N
    # sets of buffers over the same weights.
    oido.obj = WhisperModel(
        WHISPER, device="cpu", compute_type="int8",
        cpu_threads=HILOS["oido"], num_workers=OBREROS["oido"],
    )


def cargar_vector() -> None:
    from tokenizers import Tokenizer

    modelo = MODELOS / "e5/model_quantized.onnx"
    tok_ruta = MODELOS / "e5/tokenizer.json"
    if not modelo.exists() or not tok_ruta.exists():
        raise FileNotFoundError("faltan los pesos de e5 — correr `aegis ai models`")

    tok = Tokenizer.from_file(str(tok_ruta))
    # 512 is the model's ceiling. Truncate here and do not validate
    # tokens on the client's side: the character cap of the API is the
    # visible promise, and this is the belt that backs it.
    tok.enable_truncation(max_length=512)
    obj = (_sesion_onnx(modelo, HILOS["vector"]), tok)

    # THE QUANTISATION IS VERIFIED ON LOAD, not assumed. A damaged int8
    # model (or a broken export) does not raise: it gives plausible
    # vectors with the wrong neighbours. Two similar sentences have to
    # end up closer than two unrelated ones, and if that does not hold
    # it is better for the engine not to load.
    #
    # And `vector.obj` is assigned AFTER the check, not before. The first
    # version assigned first, so a failed check left the engine saying
    # `listo` with the error beside it: both signals at once, which is
    # the same as neither.
    a, b, c = _incrustar(
        obj,
        ["el gato duerme en el sofá", "un felino descansa en el sillón", "la factura vence el martes"],
        "documento",
    )
    parecidas, distintas = float(a @ b), float(a @ c)
    if parecidas <= distintas:
        raise ValueError(
            f"el modelo ordena mal las similitudes ({parecidas:.2f} <= {distintas:.2f})"
        )
    vector.obj = obj


def _incrustar(obj, textos: list[str], tipo: str) -> np.ndarray:
    """Return an (n, 384) matrix of ALREADY normalised vectors.

    The prefix belongs to the MODEL, not to the client: e5 was trained
    seeing "query: " in front of questions and "passage: " in front of
    documents, and without that prefix quality drops silently. The
    client says WHAT it is sending (query or document) and the prefix is
    applied here — the same way the voice picks the language below:
    pairs that can disagree are not sent separately.
    """
    sesion, tok = obj
    prefijo = "query: " if tipo == "consulta" else "passage: "
    lote = tok.encode_batch([prefijo + t for t in textos])

    largo = max(len(e.ids) for e in lote)
    ids = np.zeros((len(lote), largo), dtype=np.int64)
    mascara = np.zeros((len(lote), largo), dtype=np.int64)
    for i, e in enumerate(lote):
        ids[i, : len(e.ids)] = e.ids
        mascara[i, : len(e.ids)] = e.attention_mask

    # token_type_ids at zero: XLM-R does not distinguish segments, but
    # the ONNX export declares it as a required input anyway.
    (oculto,) = sesion.run(None, {
        "input_ids": ids,
        "attention_mask": mascara,
        "token_type_ids": np.zeros_like(ids),
    })

    # Average ONLY over the real tokens (the mask), and L2 at the end:
    # that is e5's recipe. Averaging the padding too would pull every
    # short text closer together, a bias that does not raise.
    m = mascara[:, :, None].astype(np.float32)
    prom = (oculto * m).sum(axis=1) / np.clip(m.sum(axis=1), 1e-9, None)
    return prom / np.clip(np.linalg.norm(prom, axis=1, keepdims=True), 1e-9, None)


def cargar_vision() -> None:
    import json

    ruta = MODELOS / "rtdetr/model.onnx"
    if not ruta.exists():
        raise FileNotFoundError("faltan los pesos de RT-DETR — correr `aegis ai models`")
    vision.obj = _sesion_onnx(ruta, HILOS["vision"])

    cfg = json.loads((MODELOS / "rtdetr/config.json").read_text())
    CLASES.update({int(k): v for k, v in cfg.get("id2label", {}).items()})
    if not CLASES:
        raise ValueError("el config.json de RT-DETR no trae id2label")


@asynccontextmanager
async def ciclo(_app: FastAPI):
    # The notice tells the local lane apart from the deployed one: in
    # the cluster there IS a signature, a NetworkPolicy and the
    # gateway's queue in front, and a notice claiming otherwise would
    # send someone hunting for a problem that does not exist.
    if os.environ.get("AEGIS_EN_CLUSTER") == "1":
        log.info("engine-cpu en el cluster: detrás del ai-gateway y su NetworkPolicy")
    else:
        log.warning("engine-cpu es el carril LOCAL: sin firma, sin cuota y sin tenant")
    for m in (voz, oido, vision, vector):
        m.limite = anyio.CapacityLimiter(m.puestos)
    for cargar, motor in ((cargar_voz, voz), (cargar_oido, oido),
                          (cargar_vision, vision), (cargar_vector, vector)):
        t0 = time.monotonic()
        try:
            cargar()
            log.info("%s listo en %.1f s", motor.nombre, time.monotonic() - t0)
        except Exception as e:  # noqa: BLE001 — one dead engine does not take the others down
            motor.error = f"{type(e).__name__}: {e}"
            log.error("%s NO cargó: %s", motor.nombre, motor.error)
    yield


app = FastAPI(title="engine-cpu", lifespan=ciclo, docs_url=None, redoc_url=None)


@app.get("/healthz")
def healthz():
    # Answers 200 even with an engine missing, the same way the gateway
    # answers with the engine switched off: a live process with an
    # absent capability is a legitimate state, and tying the probe to
    # all of them being up would make the service restart in a loop over
    # a model that was never downloaded.
    return {"ok": True}


@app.get("/v1/estado")
def estado():
    def ficha(m: Motor, modelo: str) -> dict:
        return {
            "listo": m.listo,
            "modelo": modelo,
            "puestos": m.puestos,
            # How many of those seats are free NOW. It is the signal
            # that tells "the engine is there" apart from "the engine is
            # there and there is also a turn", which until now could not
            # be seen from outside: with every seat taken the service
            # went on saying `listo` while the next request waited at
            # the door.
            "libres": int(m.limite.available_tokens) if m.limite else 0,
            # The queue and its promise: how many are waiting and how
            # long the next one would wait, computed from the MEASURED
            # cost. It is what makes it possible to tell a visitor
            # "about N seconds" instead of accepting them blindly.
            "en_fila": m.en_fila,
            "sala": m.sala,
            "espera_estimada": round(m.espera_estimada, 1),
            "costo_tipico": round(m.costo, 2),
            "error": m.error,
        }

    return {
        "carril": "cpu",
        "hilos_por_obrero": HILOS,
        "capacidades": {
            "voz": ficha(voz, "kokoro-82m-v1.0"),
            "oido": ficha(oido, f"whisper-{WHISPER}-int8"),
            "vision": ficha(vision, "rtdetr-v2-r18"),
            "vector": ficha(vector, "multilingual-e5-small-int8"),
        },
    }


# ── speech synthesis ─────────────────────────────────────────────────
# The voices on offer, with their espeak language beside them. The pair
# (voice, lang) has to be coherent: `ef_dora` reading with lang="en-us"
# pronounces Spanish with English phonemes and sounds like mockery. That
# is why the client picks a VOICE and the language comes from here,
# instead of both being sent separately and being able to disagree.
VOCES = {
    "es-f": ("ef_dora", "es", "Dora — español"),
    "es-m": ("em_alex", "es", "Alex — español"),
    "en-f": ("af_heart", "en-us", "Heart — inglés"),
    "en-m": ("am_michael", "en-us", "Michael — inglés"),
}


class PedidoVoz(BaseModel):
    texto: str
    voz: str = "es-f"
    velocidad: float = Field(default=1.0, ge=0.5, le=2.0)


@app.post("/v1/voz")
async def sintetizar(p: PedidoVoz):
    k = voz.exigir()

    texto = p.texto.strip()
    if not texto:
        raise HTTPException(400, detail={"error": "vacio", "mensaje": "No hay texto que leer."})
    if len(texto) > MAX_TEXTO_VOZ:
        raise HTTPException(400, detail={
            "error": "largo",
            "mensaje": f"El texto excede los {MAX_TEXTO_VOZ} caracteres del programa.",
        })
    if p.voz not in VOCES:
        raise HTTPException(400, detail={"error": "voz", "mensaje": "Esa voz no está instalada."})

    nombre, lang, _ = VOCES[p.voz]
    t0 = time.monotonic()
    muestras, hz = await en_obrero(
        voz, partial(k.create, texto, voice=nombre, speed=p.velocidad, lang=lang)
    )
    tardo = time.monotonic() - t0

    # Kokoro returns float32 in [-1, 1]; the WAV goes out as 16-bit PCM.
    # The clip is defensive: a peak above 1.0 would wrap the integer
    # around and sound like a click instead of clipping.
    pcm = (np.clip(muestras, -1.0, 1.0) * 32767).astype("<i2")

    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(hz)
        w.writeframes(pcm.tobytes())
    audio = buffer.getvalue()

    segundos = len(pcm) / hz
    return Response(
        content=audio,
        media_type="audio/wav",
        headers={
            # In headers and not in the body, because the body is the
            # WAV. The browser uses them to paint the status bar without
            # having to measure the audio itself.
            "X-Duracion": f"{segundos:.2f}",
            "X-Tardanza": f"{tardo:.2f}",
            "X-Voz": nombre,
            "Cache-Control": "no-store",
        },
    )


@app.get("/v1/voces")
def voces():
    return {"voces": [{"id": k, "etiqueta": e} for k, (_, _, e) in VOCES.items()]}


# ── transcription ────────────────────────────────────────────────────


@app.post("/v1/oido")
async def transcribir(audio: UploadFile = File(...), idioma: str = Form("")):
    modelo = oido.exigir()

    datos = await leer_acotado(audio, MAX_AUDIO_BYTES)
    formato_audio(datos)  # raises 415 before any parser looks at it

    t0 = time.monotonic()

    def trabajar():
        # `idioma=""` lets Whisper detect it. Pinning it is offered
        # because on short clips detection gets it wrong often, and a
        # Spanish "hola" detected as Portuguese transcribes everything
        # that follows badly.
        #
        # vad_filter trims the silence before transcribing: without it,
        # an open microphone with nobody speaking produces
        # hallucinations — Whisper fills the void with whole sentences,
        # typically subtitles that were in its training set.
        segmentos, info = modelo.transcribe(
            io.BytesIO(datos),
            language=idioma or None,
            beam_size=1,
            vad_filter=True,
            condition_on_previous_text=False,
            # ONE SINGLE TEMPERATURE, AND IT IS THE HEAVIEST FIX IN THE
            # WHOLE FILE.
            #
            # By default faster-whisper ships a LADDER of retries: 0.0,
            # 0.2, 0.4, 0.6, 0.8, 1.0. When it detects that the output
            # is repeating (compression_ratio above 2.4), it redoes the
            # WHOLE window with the next temperature, up to six times.
            #
            # MEASURED, two audios of the SAME duration (28.1 s):
            #
            #                        ladder    only 0.0
            #   normal speech         2.24s       2.09s
            #   repeated speech      10.49s       2.99s   <- 3.5x
            #
            # And the text came out the same length either way (507
            # against 511 characters): the five retries rescued nothing,
            # they only cost. It is paid always and charges exactly when
            # things are worst.
            #
            # WHY IT MATTERS SO MUCH FOR A DEMO: the first thing anybody
            # says in front of a microphone is «testing, testing». The
            # pathological input is not rare — it is the most likely one.
            #
            # And the heart of it: the input caps (8 MB, 30 s) bound what
            # COMES IN, not what it COSTS. Two audios of the same
            # duration asked for 5x the work. A queue can only promise a
            # wait if the cost per request is bounded, and this line is
            # what bounds it.
            #
            # What is lost: a genuinely difficult audio now gets one
            # attempt instead of six. For a demo, a bounded latency is
            # worth more than an occasional rescue.
            temperature=[0.0],
        )

        # THE DURATION IS CHECKED HERE, BETWEEN THESE TWO LINES, and the
        # placement is the whole point. `transcribe` returns a LAZY
        # generator: by the time it returns it has already measured the
        # audio and detected the language, but transcribed nothing yet.
        # Checking after consuming it would refuse with a correct 413
        # having done all the work anyway — a cap that saves nothing is
        # a decorative cap.
        if info.duration > MAX_AUDIO_SEG:
            raise HTTPException(413, detail={
                "error": "largo",
                "mensaje": f"El audio dura más de {MAX_AUDIO_SEG} segundos.",
            })

        # And the real work happens on this line, INSIDE the worker.
        # Moving it out would return an unconsumed generator and the work
        # would happen afterwards, back in the event loop: the limiter
        # would look installed and would be limiting nothing.
        return list(segmentos), info

    trozos, info = await en_obrero(oido, trabajar)

    return {
        "texto": " ".join(s.text.strip() for s in trozos).strip(),
        "idioma": info.language,
        "certeza": round(info.language_probability, 2),
        "duracion": round(info.duration, 2),
        "tardanza": round(time.monotonic() - t0, 2),
    }


# ── embeddings ───────────────────────────────────────────────────────

# The batch caps. The character one backs the tokeniser's truncation
# (512 tokens); the text-count one keeps a single request from occupying
# a worker for a long stretch — the unit of admission is the REQUEST, so
# a request has to cost roughly the same every time or the estimated
# wait goes back to meaning nothing.
MAX_TEXTOS_VECTOR = 16
MAX_CHARS_VECTOR = 2000


class PedidoVector(BaseModel):
    textos: list[str]
    # "documento" by default: it is the side that gets indexed in
    # batches. The query is the exception and is asked for on purpose.
    tipo: str = "documento"


@app.post("/v1/vector")
async def incrustar(p: PedidoVector):
    vector.exigir()

    if p.tipo not in ("consulta", "documento"):
        raise HTTPException(400, detail={
            "error": "tipo", "mensaje": "tipo debe ser 'consulta' o 'documento'.",
        })
    textos = [t.strip() for t in p.textos]
    if not textos or any(not t for t in textos):
        raise HTTPException(400, detail={
            "error": "vacio", "mensaje": "Llegó una lista vacía o un texto en blanco.",
        })
    if len(textos) > MAX_TEXTOS_VECTOR:
        raise HTTPException(400, detail={
            "error": "muchos", "mensaje": f"Hasta {MAX_TEXTOS_VECTOR} textos por pedido.",
        })
    if any(len(t) > MAX_CHARS_VECTOR for t in textos):
        raise HTTPException(400, detail={
            "error": "largo", "mensaje": f"Cada texto hasta {MAX_CHARS_VECTOR} caracteres.",
        })

    t0 = time.monotonic()
    matriz = await en_obrero(vector, partial(_incrustar, vector.obj, textos, p.tipo))
    return {
        "vectores": [[round(float(x), 6) for x in fila] for fila in matriz],
        "dim": int(matriz.shape[1]),
        "tardanza": round(time.monotonic() - t0, 3),
    }


# ── object detection ─────────────────────────────────────────────────

LADO = 640  # RT-DETRv2 expects a fixed 640x640


def _solape(a: np.ndarray, b: np.ndarray) -> float:
    """IoU of two boxes in (x1, y1, x2, y2)."""
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    comun = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    if comun <= 0:
        return 0.0
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    return float(comun / (area_a + area_b - comun))


@app.post("/v1/vision")
async def detectar(imagen: UploadFile = File(...), umbral: float = Form(0.5)):
    sesion = vision.exigir()

    datos = await leer_acotado(imagen, MAX_IMAGEN_BYTES)
    formato_imagen(datos)

    from PIL import Image

    # Pixel cap against the decompression bomb: a 50 KB PNG can declare
    # 40,000 x 40,000 and blow up RAM on opening. The limit is set
    # BEFORE the open, which is where Pillow consults it.
    Image.MAX_IMAGE_PIXELS = 40_000_000
    try:
        img = Image.open(io.BytesIO(datos))
        img.verify()                       # validates the structure without decoding
        img = Image.open(io.BytesIO(datos)).convert("RGB")
    except Exception:
        raise HTTPException(415, detail={
            "error": "formato", "mensaje": "La imagen está dañada o incompleta.",
        }) from None

    ancho, alto = img.size
    t0 = time.monotonic()

    # RT-DETR does NOT preserve the aspect ratio: it expects a stretched
    # 640x640, and its output comes back in relative coordinates [0,1]
    # over THAT box. Since the stretch is the same in both directions,
    # undoing it is multiplying by the original width and height — with
    # no letterbox padding to subtract.
    lienzo = img.resize((LADO, LADO), Image.BILINEAR)
    # Divide by 255 and NOTHING ELSE. Its preprocessor_config.json says
    # `do_normalize: false`, which is the opposite of almost the whole
    # vision family: the ImageNet mean is not subtracted and its
    # deviation is not divided out. Subtracting them "because that is
    # what one always does" would give plausible and shifted boxes — the
    # expensive failure, the one that does not raise.
    x = np.asarray(lienzo, dtype=np.float32) / 255.0
    x = x.transpose(2, 0, 1)[None]         # HWC -> NCHW

    entrada = sesion.get_inputs()[0].name
    salidas = await en_obrero(vision, partial(sesion.run, None, {entrada: x}))

    nombres = [s.name for s in sesion.get_outputs()]
    porNombre = dict(zip(nombres, salidas))
    logits = porNombre.get("logits", salidas[0])[0]        # (300, 80)
    cajas = porNombre.get("pred_boxes", salidas[1])[0]     # (300, 4) cx cy w h

    # SIGMOID and not softmax. RT-DETR trains with focal loss, so every
    # class scores separately and there is no "background class" taking
    # the remainder. With softmax the numbers would come out plausible
    # but badly calibrated, and the threshold would stop meaning what it
    # says.
    puntajes = 1.0 / (1.0 + np.exp(-logits))
    mejor = puntajes.argmax(axis=1)
    conf = puntajes[np.arange(len(mejor)), mejor]

    objetos = []
    puestas: list[tuple[int, np.ndarray]] = []
    for i in np.argsort(-conf):
        if conf[i] < umbral:
            break                          # they come sorted: the rest fails too
        cx, cy, w, h = cajas[i]

        # Overlap suppression, within the same class. RT-DETR advertises
        # itself as "NMS-free" and generally delivers, but MEASURED
        # here: on the test photo it returned the sofa TWICE with boxes
        # overlapping by more than 99%. Counting five objects where
        # there are four is an error that does not raise — the output
        # reads perfectly well and is wrong — so it is filtered.
        #
        # The threshold is high (0.7) on purpose: two cats sitting
        # together share a fair amount of box, and lowering it would
        # start erasing real objects. What is suppressed is the
        # duplicate, not the neighbour.
        actual = np.array([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2])
        clase = int(mejor[i])
        if any(c == clase and _solape(actual, previa) > 0.7 for c, previa in puestas):
            continue
        puestas.append((clase, actual))

        objetos.append({
            "clase": CLASES.get(int(mejor[i]), str(int(mejor[i]))),
            "confianza": round(float(conf[i]), 3),
            # Percentages and not pixels: the browser draws the box over
            # an image it has already scaled to its liking, and in
            # pixels it would have to redo the arithmetic — and get it
            # wrong — on every resize.
            "caja": {
                "x": round(float(cx - w / 2) * 100, 2),
                "y": round(float(cy - h / 2) * 100, 2),
                "ancho": round(float(w) * 100, 2),
                "alto": round(float(h) * 100, 2),
            },
        })
        if len(objetos) >= 20:
            break

    return {
        "objetos": objetos,
        "medida": {"ancho": ancho, "alto": alto},
        "tardanza": round(time.monotonic() - t0, 3),
    }


@app.exception_handler(HTTPException)
async def error_json(_req, exc: HTTPException):
    # Uniforms the shape of the error. FastAPI wraps `detail` as-is, and
    # without this one route would return {"detail": {...}} and another
    # {"detail": "text"}: the client would have to know which is which.
    #
    # `headers=exc.headers` is NOT optional: the 429 from admission
    # travels with its Retry-After, and rebuilding the response without
    # the exception's headers — which is what this handler used to do —
    # dropped it silently. A 429 with no Retry-After is a "come back
    # whenever you like".
    d = exc.detail if isinstance(exc.detail, dict) else {"error": "error", "mensaje": str(exc.detail)}
    return JSONResponse(status_code=exc.status_code, content=d, headers=exc.headers)
