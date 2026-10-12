package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname()
		fmt.Fprintf(w, "Hello from ${{ values.name }} on %s\n", host)
	})

	addr := ":8080"
	log.Printf("${{ values.name }} listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
