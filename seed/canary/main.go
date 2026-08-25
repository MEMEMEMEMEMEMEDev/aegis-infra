// hello-aegis v2 — the platform's minimal canary. Its only purpose is
// to exercise the complete path: build → scan → push → sign → deploy
// → write-back. DISPOSABLE REPO.
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname()
		fmt.Fprintf(w, "hello-aegis v2 canary — pod %s\n", host)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	_ = http.ListenAndServe(":8080", nil)
}
