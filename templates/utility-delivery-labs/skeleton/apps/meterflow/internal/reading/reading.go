// Package reading defines the wire format between concentrators and the head-end.
package reading

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Reading is one meter's consumption for one interval.
type Reading struct {
	MeterID     string    `json:"meter_id"`
	IntervalEnd time.Time `json:"interval_end"`
	KWh         float64   `json:"kwh"`
}

// Batch is what a concentrator sends: many readings in one request.
type Batch struct {
	Concentrator string    `json:"concentrator"`
	Readings     []Reading `json:"readings"`
}

// Result is the head-end's answer to a batch.
type Result struct {
	Accepted   int `json:"accepted"`
	Duplicates int `json:"duplicates"`
	Rejected   int `json:"rejected"`
}

// MeterID formats meter number n (1-based) as M0000001.
func MeterID(n int) string { return fmt.Sprintf("M%07d", n) }

// MeterNumber parses M0000001 back to 1. It returns 0 for anything malformed.
func MeterNumber(id string) int {
	if len(id) != 8 || !strings.HasPrefix(id, "M") {
		return 0
	}
	n, err := strconv.Atoi(id[1:])
	if err != nil || n < 1 {
		return 0
	}
	return n
}
