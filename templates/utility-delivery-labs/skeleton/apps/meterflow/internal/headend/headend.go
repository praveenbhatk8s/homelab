// Package headend validates and stores meter readings.
//
// Storage is in memory to keep the lab self-contained. Lab 06 replaces it with PostgreSQL, where a
// unique key on (meter_id, interval_end) does the deduplication across replicas that this
// in-memory store can only do per replica.
package headend

import (
	"math"
	"sync"
	"time"

	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/reading"
)

// Outcome is what happened to one reading.
type Outcome string

// Possible outcomes. Rejection reasons double as metric labels, so keep them short and stable.
const (
	Stored       Outcome = "stored"
	Duplicate    Outcome = "duplicate"
	UnknownMeter Outcome = "unknown_meter"
	Misaligned   Outcome = "misaligned"
	Future       Outcome = "future"
	TooOld       Outcome = "too_old"
	Implausible  Outcome = "implausible"
)

// Config controls validation.
type Config struct {
	MeterCount int           // meters 1..MeterCount are registered
	Interval   time.Duration // reading interval, for example 15 minutes
	MaxAge     time.Duration // oldest interval still accepted; concentrators may replay after an outage
	MaxKWh     float64       // a single interval above this is implausible for a household meter
}

// Store keeps which (meter, interval) pairs it has seen.
type Store struct {
	cfg  Config
	now  func() time.Time
	mu   sync.Mutex
	seen map[int64]map[int]struct{} // interval end (unix seconds) -> meter numbers
}

// NewStore returns an empty store. now is injectable for tests; pass time.Now in production.
func NewStore(cfg Config, now func() time.Time) *Store {
	return &Store{cfg: cfg, now: now, seen: map[int64]map[int]struct{}{}}
}

// Ingest validates one reading and stores it if valid and new.
func (s *Store) Ingest(r reading.Reading) Outcome {
	n := reading.MeterNumber(r.MeterID)
	if n == 0 || n > s.cfg.MeterCount {
		return UnknownMeter
	}
	end := r.IntervalEnd.UTC()
	if !end.Truncate(s.cfg.Interval).Equal(end) {
		return Misaligned
	}
	now := s.now().UTC()
	if end.After(now.Add(s.cfg.Interval)) {
		return Future
	}
	if now.Sub(end) > s.cfg.MaxAge {
		return TooOld
	}
	if math.IsNaN(r.KWh) || r.KWh < 0 || r.KWh > s.cfg.MaxKWh {
		return Implausible
	}

	key := end.Unix()
	s.mu.Lock()
	defer s.mu.Unlock()
	meters, ok := s.seen[key]
	if !ok {
		meters = map[int]struct{}{}
		s.seen[key] = meters
	}
	if _, dup := meters[n]; dup {
		return Duplicate
	}
	meters[n] = struct{}{}
	return Stored
}

// Prune drops intervals older than MaxAge, which can no longer receive readings.
func (s *Store) Prune() {
	cutoff := s.now().UTC().Add(-s.cfg.MaxAge).Unix()
	s.mu.Lock()
	defer s.mu.Unlock()
	for k := range s.seen {
		if k < cutoff {
			delete(s.seen, k)
		}
	}
}

// Intervals returns how many intervals are currently tracked.
func (s *Store) Intervals() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.seen)
}
