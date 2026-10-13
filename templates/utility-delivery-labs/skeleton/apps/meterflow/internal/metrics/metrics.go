// Package metrics is a minimal Prometheus text-format exposition, so MeterFlow builds with the
// standard library only. A production service would use the official client library.
package metrics

import (
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
)

type metric interface {
	write(w io.Writer)
}

// Registry holds metrics and serves them on /metrics.
type Registry struct {
	mu      sync.Mutex
	metrics []metric
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry { return &Registry{} }

func (r *Registry) add(m metric) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.metrics = append(r.metrics, m)
}

// Handler serves all registered metrics in Prometheus text format.
func (r *Registry) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		r.mu.Lock()
		defer r.mu.Unlock()
		for _, m := range r.metrics {
			m.write(w)
		}
	})
}

// Labels renders label pairs, for example Labels("reason", "late") gives reason="late".
func Labels(kv ...string) string {
	if len(kv)%2 != 0 {
		panic("metrics.Labels needs key/value pairs")
	}
	parts := make([]string, 0, len(kv)/2)
	for i := 0; i < len(kv); i += 2 {
		v := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`).Replace(kv[i+1])
		parts = append(parts, fmt.Sprintf(`%s="%s"`, kv[i], v))
	}
	return strings.Join(parts, ",")
}

type series struct {
	name, help, kind string
	mu               sync.Mutex
	values           map[string]float64
}

func newSeries(r *Registry, name, help, kind string) *series {
	s := &series{name: name, help: help, kind: kind, values: map[string]float64{}}
	r.add(s)
	return s
}

func (s *series) write(w io.Writer) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fmt.Fprintf(w, "# HELP %s %s\n# TYPE %s %s\n", s.name, s.help, s.name, s.kind)
	keys := make([]string, 0, len(s.values))
	for k := range s.values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if k == "" {
			fmt.Fprintf(w, "%s %g\n", s.name, s.values[k])
		} else {
			fmt.Fprintf(w, "%s{%s} %g\n", s.name, k, s.values[k])
		}
	}
}

// Counter only goes up.
type Counter struct{ s *series }

// NewCounter registers a counter. Name it with a _total suffix.
func NewCounter(r *Registry, name, help string) *Counter {
	c := &Counter{s: newSeries(r, name, help, "counter")}
	c.s.values[""] = 0
	return c
}

// Add increases the unlabelled counter.
func (c *Counter) Add(v float64) { c.AddWith("", v) }

// AddWith increases the counter for a label set built with Labels.
func (c *Counter) AddWith(labels string, v float64) {
	if v < 0 {
		return
	}
	c.s.mu.Lock()
	if labels != "" {
		delete(c.s.values, "") // a labelled counter should not also show an unlabelled zero
	}
	c.s.values[labels] += v
	c.s.mu.Unlock()
}

// Gauge can go up and down.
type Gauge struct{ s *series }

// NewGauge registers a gauge.
func NewGauge(r *Registry, name, help string) *Gauge {
	return &Gauge{s: newSeries(r, name, help, "gauge")}
}

// Set sets the unlabelled gauge.
func (g *Gauge) Set(v float64) {
	g.s.mu.Lock()
	g.s.values[""] = v
	g.s.mu.Unlock()
}

// Summary tracks a count and a sum, enough for average latency in PromQL.
type Summary struct {
	name, help string
	mu         sync.Mutex
	count, sum float64
}

// NewSummary registers a summary without quantiles.
func NewSummary(r *Registry, name, help string) *Summary {
	s := &Summary{name: name, help: help}
	r.add(s)
	return s
}

// Observe records one value.
func (s *Summary) Observe(v float64) {
	s.mu.Lock()
	s.count++
	s.sum += v
	s.mu.Unlock()
}

func (s *Summary) write(w io.Writer) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fmt.Fprintf(w, "# HELP %s %s\n# TYPE %s summary\n%s_sum %g\n%s_count %g\n",
		s.name, s.help, s.name, s.name, s.sum, s.name, s.count)
}
