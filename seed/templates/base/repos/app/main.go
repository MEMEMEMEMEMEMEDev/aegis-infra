// __ORG__-app — the initial HTTP service of the __ORG__ organization.
//
// It was born from aegis's `base` template and from that moment on it
// is YOURS: the template never touches it again. Zero external
// dependencies on purpose (Go's stdlib is enough to serve HTTP): an
// empty dependency tree is a tree that does not rot.
//
// The only thing the platform asks of this process is that it listen
// on the port the contract declares (8080) and answer /healthz — the
// Deployment's readinessProbe queries it. The rest is your app.
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname()
		fmt.Fprintf(w, "__ORG__ — initial app of the base template, pod %s\n", host)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	_ = http.ListenAndServe(":8080", nil)
}
