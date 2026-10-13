// Command headend receives meter readings from concentrators.
//
// Configuration is by environment variable, so the same image runs unchanged on AKS and OpenShift:
//
//	LISTEN_ADDR      API address (default :8080)
//	METRICS_ADDR     metrics and health address (default :9090)
//	METER_COUNT      registered meters, M0000001..N (default 1000)
//	INTERVAL         reading interval (default 15m; use a few seconds in labs)
//	MAX_AGE          oldest interval accepted, for replay after outages (default 48h)
//	TLS_CERT_FILE    serve HTTPS with this certificate; reloaded when the file changes
//	TLS_KEY_FILE     key for TLS_CERT_FILE
//	DRAIN_DELAY      how long to keep serving after SIGTERM while endpoints update (default 5s)
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/headend"
	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/metrics"
	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/reading"
)

const maxBodyBytes = 5 << 20 // 5 MiB, about 50,000 readings

type server struct {
	store    *headend.Store
	log      *slog.Logger
	draining atomic.Bool

	received   *metrics.Counter
	stored     *metrics.Counter
	duplicates *metrics.Counter
	rejected   *metrics.Counter
	batches    *metrics.Counter
	latency    *metrics.Summary
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(log); err != nil {
		log.Error("exiting", "error", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg := headend.Config{
		MeterCount: envInt("METER_COUNT", 1000),
		Interval:   envDuration("INTERVAL", 15*time.Minute),
		MaxAge:     envDuration("MAX_AGE", 48*time.Hour),
		MaxKWh:     50,
	}
	listen := envString("LISTEN_ADDR", ":8080")
	metricsAddr := envString("METRICS_ADDR", ":9090")
	drainDelay := envDuration("DRAIN_DELAY", 5*time.Second)
	certFile, keyFile := os.Getenv("TLS_CERT_FILE"), os.Getenv("TLS_KEY_FILE")

	reg := metrics.NewRegistry()
	s := &server{
		store:      headend.NewStore(cfg, time.Now),
		log:        log,
		received:   metrics.NewCounter(reg, "meterflow_readings_received_total", "Readings received, valid or not."),
		stored:     metrics.NewCounter(reg, "meterflow_readings_stored_total", "Readings stored for the first time."),
		duplicates: metrics.NewCounter(reg, "meterflow_readings_duplicate_total", "Readings already stored; accepted idempotently."),
		rejected:   metrics.NewCounter(reg, "meterflow_readings_rejected_total", "Readings rejected by validation, by reason."),
		batches:    metrics.NewCounter(reg, "meterflow_batches_total", "Batches received, by HTTP status code."),
		latency:    metrics.NewSummary(reg, "meterflow_batch_duration_seconds", "Time to process one batch."),
	}
	metrics.NewGauge(reg, "meterflow_registered_meters", "Meters expected to report each interval.").Set(float64(cfg.MeterCount))
	metrics.NewGauge(reg, "meterflow_interval_seconds", "Reading interval in seconds.").Set(cfg.Interval.Seconds())
	certExpiry := metrics.NewGauge(reg, "meterflow_tls_certificate_expiry_timestamp_seconds", "NotAfter of the serving certificate, as a Unix timestamp. Alert well before it.")

	api := http.NewServeMux()
	api.HandleFunc("POST /v1/readings", s.handleReadings)

	ops := http.NewServeMux()
	ops.Handle("GET /metrics", reg.Handler())
	ops.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	ops.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if s.draining.Load() {
			http.Error(w, "draining", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	apiSrv := &http.Server{Addr: listen, Handler: api, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second}
	opsSrv := &http.Server{Addr: metricsAddr, Handler: ops, ReadHeaderTimeout: 5 * time.Second}

	useTLS := certFile != "" && keyFile != ""
	if useTLS {
		cr := &certReloader{certFile: certFile, keyFile: keyFile, log: log, onLoad: func(c *x509.Certificate) {
			certExpiry.Set(float64(c.NotAfter.Unix()))
		}}
		if _, err := cr.get(); err != nil {
			return fmt.Errorf("loading TLS certificate: %w", err)
		}
		apiSrv.TLSConfig = &tls.Config{
			MinVersion:     tls.VersionTLS12,
			GetCertificate: func(*tls.ClientHelloInfo) (*tls.Certificate, error) { return cr.get() },
		}
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	go s.pruneLoop(ctx)

	errs := make(chan error, 2)
	go func() {
		log.Info("metrics listening", "addr", metricsAddr)
		errs <- opsSrv.ListenAndServe()
	}()
	go func() {
		log.Info("api listening", "addr", listen, "tls", useTLS, "meters", cfg.MeterCount, "interval", cfg.Interval.String())
		if useTLS {
			errs <- apiSrv.ListenAndServeTLS("", "")
		} else {
			errs <- apiSrv.ListenAndServe()
		}
	}()

	select {
	case err := <-errs:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
	}

	// Graceful shutdown: fail readiness first so Kubernetes removes this pod from the Service,
	// keep serving while that propagates, then stop accepting and finish in-flight batches.
	log.Info("draining", "delay", drainDelay.String())
	s.draining.Store(true)
	time.Sleep(drainDelay)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := apiSrv.Shutdown(shutdownCtx); err != nil {
		log.Error("api shutdown", "error", err)
	}
	_ = opsSrv.Shutdown(shutdownCtx)
	log.Info("stopped")
	return nil
}

func (s *server) handleReadings(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	status := http.StatusOK
	defer func() {
		s.batches.AddWith(metrics.Labels("code", strconv.Itoa(status)), 1)
		s.latency.Observe(time.Since(start).Seconds())
	}()

	if s.draining.Load() {
		status = http.StatusServiceUnavailable
		http.Error(w, "draining, retry", status)
		return
	}

	var b reading.Batch
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&b); err != nil {
		status = http.StatusBadRequest
		s.rejected.AddWith(metrics.Labels("reason", "malformed_batch"), 1)
		http.Error(w, "malformed batch: "+err.Error(), status)
		return
	}

	var res reading.Result
	for _, rd := range b.Readings {
		s.received.Add(1)
		switch out := s.store.Ingest(rd); out {
		case headend.Stored:
			res.Accepted++
			s.stored.Add(1)
		case headend.Duplicate:
			res.Duplicates++
			s.duplicates.Add(1)
		default:
			res.Rejected++
			s.rejected.AddWith(metrics.Labels("reason", string(out)), 1)
		}
	}

	if res.Rejected > 0 {
		s.log.Warn("batch had rejected readings", "concentrator", b.Concentrator, "rejected", res.Rejected, "total", len(b.Readings))
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(res)
}

func (s *server) pruneLoop(ctx context.Context) {
	t := time.NewTicker(time.Minute)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.store.Prune()
		}
	}
}

// certReloader re-reads the certificate when the file changes, so cert-manager can rotate it
// without a restart. Kubernetes updates mounted Secrets in place, usually within a minute.
type certReloader struct {
	certFile, keyFile string
	log               *slog.Logger
	onLoad            func(*x509.Certificate)

	mu      sync.Mutex
	cert    *tls.Certificate
	modTime time.Time
	checked time.Time
}

func (c *certReloader) get() (*tls.Certificate, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cert != nil && time.Since(c.checked) < 10*time.Second {
		return c.cert, nil
	}
	c.checked = time.Now()

	fi, err := os.Stat(c.certFile)
	if err != nil {
		if c.cert != nil {
			return c.cert, nil // keep serving the last good certificate
		}
		return nil, err
	}
	if c.cert != nil && fi.ModTime().Equal(c.modTime) {
		return c.cert, nil
	}

	pair, err := tls.LoadX509KeyPair(c.certFile, c.keyFile)
	if err != nil {
		if c.cert != nil {
			c.log.Error("certificate reload failed, keeping previous", "error", err)
			return c.cert, nil
		}
		return nil, err
	}
	leaf, err := x509.ParseCertificate(pair.Certificate[0])
	if err != nil {
		return nil, err
	}
	pair.Leaf = leaf
	c.cert, c.modTime = &pair, fi.ModTime()
	c.log.Info("certificate loaded", "subject", leaf.Subject.String(), "not_after", leaf.NotAfter.Format(time.RFC3339), "dns_names", leaf.DNSNames)
	if c.onLoad != nil {
		c.onLoad(leaf)
	}
	return c.cert, nil
}

func envString(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return def
}

func envDuration(key string, def time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil && d > 0 {
			return d
		}
	}
	return def
}
