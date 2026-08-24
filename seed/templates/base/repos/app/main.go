// __ORG__-app — el servicio HTTP inicial de la organización __ORG__.
//
// Nació de la plantilla `base` de aegis y desde ese momento es TUYO:
// la plantilla no vuelve a tocarlo. Cero dependencias externas a
// propósito (la stdlib de Go alcanza para servir HTTP): un árbol de
// dependencias vacío es un árbol que no se pudre.
//
// Lo único que la plataforma le pide a este proceso es que escuche en
// el puerto que declara el contrato (8080) y responda /healthz — el
// readinessProbe del Deployment lo consulta. El resto es tu app.
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname()
		fmt.Fprintf(w, "__ORG__ — app inicial de la plantilla base, pod %s\n", host)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	_ = http.ListenAndServe(":8080", nil)
}
