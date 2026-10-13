package headend

import (
	"math"
	"testing"
	"time"

	"github.com/praveenbhatk8s/utility-platform-delivery-labs/apps/meterflow/internal/reading"
)

func testStore(now time.Time) *Store {
	return NewStore(Config{
		MeterCount: 100,
		Interval:   15 * time.Minute,
		MaxAge:     48 * time.Hour,
		MaxKWh:     50,
	}, func() time.Time { return now })
}

func TestIngest(t *testing.T) {
	now := time.Date(2026, 10, 13, 10, 20, 0, 0, time.UTC)
	end := time.Date(2026, 10, 13, 10, 15, 0, 0, time.UTC)

	cases := []struct {
		name string
		r    reading.Reading
		want Outcome
	}{
		{"valid", reading.Reading{MeterID: "M0000001", IntervalEnd: end, KWh: 0.2}, Stored},
		{"unknown meter number", reading.Reading{MeterID: "M0000101", IntervalEnd: end, KWh: 0.2}, UnknownMeter},
		{"malformed meter id", reading.Reading{MeterID: "meter-1", IntervalEnd: end, KWh: 0.2}, UnknownMeter},
		{"not on an interval boundary", reading.Reading{MeterID: "M0000002", IntervalEnd: end.Add(time.Minute), KWh: 0.2}, Misaligned},
		{"from the future", reading.Reading{MeterID: "M0000003", IntervalEnd: end.Add(time.Hour), KWh: 0.2}, Future},
		{"older than max age", reading.Reading{MeterID: "M0000004", IntervalEnd: end.Add(-72 * time.Hour), KWh: 0.2}, TooOld},
		{"negative consumption", reading.Reading{MeterID: "M0000005", IntervalEnd: end, KWh: -1}, Implausible},
		{"impossible consumption", reading.Reading{MeterID: "M0000006", IntervalEnd: end, KWh: 500}, Implausible},
		{"not a number", reading.Reading{MeterID: "M0000007", IntervalEnd: end, KWh: math.NaN()}, Implausible},
		{"replayed after outage, within max age", reading.Reading{MeterID: "M0000008", IntervalEnd: end.Add(-4 * time.Hour), KWh: 0.2}, Stored},
	}

	s := testStore(now)
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := s.Ingest(tc.r); got != tc.want {
				t.Fatalf("got %s, want %s", got, tc.want)
			}
		})
	}
}

func TestDuplicateIsDetected(t *testing.T) {
	now := time.Date(2026, 10, 13, 10, 20, 0, 0, time.UTC)
	end := time.Date(2026, 10, 13, 10, 15, 0, 0, time.UTC)
	s := testStore(now)
	r := reading.Reading{MeterID: "M0000001", IntervalEnd: end, KWh: 0.2}

	if got := s.Ingest(r); got != Stored {
		t.Fatalf("first ingest: got %s", got)
	}
	if got := s.Ingest(r); got != Duplicate {
		t.Fatalf("second ingest: got %s, want duplicate", got)
	}
}

func TestPruneDropsOldIntervals(t *testing.T) {
	now := time.Date(2026, 10, 13, 10, 20, 0, 0, time.UTC)
	current := now
	s := NewStore(Config{MeterCount: 10, Interval: 15 * time.Minute, MaxAge: time.Hour, MaxKWh: 50},
		func() time.Time { return current })

	s.Ingest(reading.Reading{MeterID: "M0000001", IntervalEnd: time.Date(2026, 10, 13, 10, 0, 0, 0, time.UTC), KWh: 1})
	if s.Intervals() != 1 {
		t.Fatalf("want 1 interval tracked, got %d", s.Intervals())
	}

	current = now.Add(2 * time.Hour)
	s.Prune()
	if s.Intervals() != 0 {
		t.Fatalf("want 0 intervals after prune, got %d", s.Intervals())
	}
}
