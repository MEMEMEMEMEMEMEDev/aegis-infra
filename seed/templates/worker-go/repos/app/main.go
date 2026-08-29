// __ORG__-app — the initial worker of the __ORG__ organization.
//
// It was born from aegis's `worker-go` template and from that moment on
// it is YOURS: the template never touches it again. Zero external
// dependencies on purpose (Go's stdlib is enough to loop and to log):
// an empty dependency tree is a tree that does not rot.
//
// A WORKER HAS NO PROBE, so the two things below are how anybody finds
// out it is alive: it logs each pass, and it exits cleanly on SIGTERM.
// The second one is not decoration — a process that ignores SIGTERM is
// killed 30 seconds later by the kubelet, every rollout takes that long
// per pod, and a job interrupted mid-flight leaves the half-written
// state the graceful path exists to avoid.
package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// The pause between passes. It is a constant and not an environment
// variable on purpose: a value that changes behaviour belongs to the
// deployment, and the day it does, it comes in as one — declared, in
// git, and visible in the diff.
const every = 30 * time.Second

func main() {
	// The context is cancelled on SIGTERM (the rollout) and on SIGINT
	// (a hand on the keyboard).
	ctx, stop := signal.NotifyContext(context.Background(),
		syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	host, _ := os.Hostname()
	log.Printf("__ORG__ worker starting on pod %s, one pass every %s", host, every)

	t := time.NewTicker(every)
	defer t.Stop()
	for {
		if err := work(ctx); err != nil {
			// Logged and NOT fatal: a failed pass is not a dead
			// worker, and exiting here would turn a transient error
			// into a CrashLoopBackOff that hides how often it fails.
			log.Printf("pass failed: %v", err)
		}
		select {
		case <-ctx.Done():
			log.Printf("SIGTERM received: finishing cleanly")
			return
		case <-t.C:
		}
	}
}

// work is one pass. Replace it with yours; keep it taking the context,
// so that whatever it calls is cancelled when the pod is asked to stop.
func work(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		// Already asked to stop: do not start a pass that will be
		// interrupted halfway.
		return nil
	}
	log.Printf("pass done")
	return nil
}
