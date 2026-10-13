// Command meter-sim plays a set of concentrators sending meter readings to the head-end.
//
// It behaves like the real thing in the ways that matter for operations: readings arrive in a
// burst after each interval, and when the head-end is unreachable each concentrator buffers its
// readings and replays them later. That is what makes a four-hour RTO acceptable for a utility.
//
//	TARGET          head-end URL (default https://meterflow.meterflow.svc:8080/v1/readings)
//	METERS          number of meters (default 1000)
//	CONCENTRATORS   number of concentrators the meters are split across (default 10)
//	INTERVAL        reading interval; must match the head-end (default 15m)
//	JITTER          spread of send times after each interval (default INTERVAL/3)
//	DROP_RATE       fraction of readings a meter fails to produce, 0 to 1 (default 0)
//	BUFFER_LIMIT    readings a concentrator can hold while the head-end is down (default 200000)
//	CA_FILE         CA bundle to verify the head-end's certificate
//	METRICS_ADDR    metrics address (default :9091)
package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/metrics"
	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/reading"
)

const chunkSize = 2000

type sim struct {
	target      string
	client      *http.Client
	log         *slog.Logger
	interval    time.Duration
	jitter      time.Duration
	dropRate    float64
	bufferLimit int

	generated *metrics.Counter
	dropped   *metrics.Counter
	acked     *metrics.Counter
	rejected  *metrics.Counter
	lost      *metrics.Counter
	errors    *metrics.Counter
	buffered  *metrics.Gauge

	mu        sync.Mutex
	bufferSum map[string]int
}

type concentrator struct {
	id     string
	meters []int
	mu     sync.Mutex
	buffer []reading.Reading
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(log); err != nil {
		log.Error("exiting", "error", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	meters := envInt("METERS", 1000)
	nConc := envInt("CONCENTRATORS", 10)
	interval := envDuration("INTERVAL", 15*time.Minute)

	client, err := httpClient(os.Getenv("CA_FILE"))
	if err != nil {
		return err
	}

	reg := metrics.NewRegistry()
	s := &sim{
		target:      envString("TARGET", "https://meterflow.meterflow.svc:8080/v1/readings"),
		client:      client,
		log:         log,
		interval:    interval,
		jitter:      envDuration("JITTER", interval/3),
		dropRate:    envFloat("DROP_RATE", 0),
		bufferLimit: envInt("BUFFER_LIMIT", 200000),
		generated:   metrics.NewCounter(reg, "meter_sim_readings_generated_total", "Readings produced by meters."),
		dropped:     metrics.NewCounter(reg, "meter_sim_readings_dropped_total", "Readings meters failed to produce (DROP_RATE)."),
		acked:       metrics.NewCounter(reg, "meter_sim_readings_acked_total", "Readings the head-end accepted or already had."),
		rejected:    metrics.NewCounter(reg, "meter_sim_readings_rejected_total", "Readings the head-end rejected."),
		lost:        metrics.NewCounter(reg, "meter_sim_readings_lost_total", "Readings discarded because a concentrator buffer was full."),
		errors:      metrics.NewCounter(reg, "meter_sim_post_errors_total", "Failed POSTs to the head-end."),
		buffered:    metrics.NewGauge(reg, "meter_sim_buffered_readings", "Readings waiting in concentrator buffers."),
		bufferSum:   map[string]int{},
	}

	concs := make([]*concentrator, nConc)
	for i := range concs {
		concs[i] = &concentrator{id: fmt.Sprintf("C%03d", i+1)}
	}
	for m := 1; m <= meters; m++ {
		c := concs[(m-1)%nConc]
		c.meters = append(c.meters, m)
	}

	go func() {
		mux := http.NewServeMux()
		mux.Handle("GET /metrics", reg.Handler())
		mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
		srv := &http.Server{Addr: envString("METRICS_ADDR", ":9091"), Handler: mux, ReadHeaderTimeout: 5 * time.Second}
		log.Error("metrics server", "error", srv.ListenAndServe())
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	log.Info("starting", "target", s.target, "meters", meters, "concentrators", nConc, "interval", interval.String(), "drop_rate", s.dropRate)

	for {
		next := time.Now().Truncate(interval).Add(interval)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(time.Until(next)):
		}
		for _, c := range concs {
			s.produce(c, next)
			go s.flushAfterJitter(ctx, c)
		}
	}
}

// produce adds this interval's readings to the concentrator's buffer.
func (s *sim) produce(c *concentrator, end time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, m := range c.meters {
		if s.dropRate > 0 && rand.Float64() < s.dropRate {
			s.dropped.Add(1)
			continue
		}
		if len(c.buffer) >= s.bufferLimit {
			s.lost.Add(1)
			continue
		}
		c.buffer = append(c.buffer, reading.Reading{
			MeterID:     reading.MeterID(m),
			IntervalEnd: end.UTC(),
			KWh:         0.05 + rand.Float64()*0.45,
		})
		s.generated.Add(1)
	}
	s.setBuffered(c.id, len(c.buffer))
}

func (s *sim) flushAfterJitter(ctx context.Context, c *concentrator) {
	if s.jitter > 0 {
		select {
		case <-ctx.Done():
			return
		case <-time.After(rand.N(s.jitter)):
		}
	}
	s.flush(ctx, c)
}

// flush sends the buffer in chunks. Anything not acknowledged stays buffered for the next interval.
func (s *sim) flush(ctx context.Context, c *concentrator) {
	c.mu.Lock()
	defer c.mu.Unlock()

	for len(c.buffer) > 0 {
		n := min(chunkSize, len(c.buffer))
		res, err := s.post(ctx, reading.Batch{Concentrator: c.id, Readings: c.buffer[:n]})
		if err != nil {
			s.errors.Add(1)
			s.log.Warn("head-end unreachable, keeping readings buffered", "concentrator", c.id, "buffered", len(c.buffer), "error", err)
			break
		}
		s.acked.Add(float64(res.Accepted + res.Duplicates))
		s.rejected.Add(float64(res.Rejected))
		c.buffer = c.buffer[n:]
	}
	if len(c.buffer) == 0 {
		c.buffer = nil // release memory after a large replay
	}
	s.setBuffered(c.id, len(c.buffer))
}

func (s *sim) post(ctx context.Context, b reading.Batch) (reading.Result, error) {
	var res reading.Result
	body, err := json.Marshal(b)
	if err != nil {
		return res, err
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.target, bytes.NewReader(body))
	if err != nil {
		return res, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return res, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return res, fmt.Errorf("head-end returned %s", resp.Status)
	}
	return res, json.NewDecoder(resp.Body).Decode(&res)
}

func (s *sim) setBuffered(id string, n int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.bufferSum[id] = n
	total := 0
	for _, v := range s.bufferSum {
		total += v
	}
	s.buffered.Set(float64(total))
}

func httpClient(caFile string) (*http.Client, error) {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12}
	if caFile != "" {
		pem, err := os.ReadFile(caFile)
		if err != nil {
			return nil, fmt.Errorf("reading CA_FILE: %w", err)
		}
		pool := x509.NewCertPool()
		if !pool.AppendCertsFromPEM(pem) {
			return nil, fmt.Errorf("no certificates found in %s", caFile)
		}
		tr.TLSClientConfig.RootCAs = pool
	}
	return &http.Client{Transport: tr}, nil
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

func envFloat(key string, def float64) float64 {
	if v := os.Getenv(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil && f >= 0 && f <= 1 {
			return f
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
