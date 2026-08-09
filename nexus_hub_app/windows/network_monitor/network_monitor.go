package main

/*
#include <stdint.h>
*/
import "C"

import (
	"strings"
	"sync/atomic"
	"time"

	"github.com/shirou/gopsutil/v4/net"
)

// Cumulative totals (since the DLL started) and last sample-window deltas.
var (
	started   int32
	lastRecv  uint64
	lastSent  uint64
	deltaRecv uint64 // bytes in last 1s sample window
	deltaSent uint64
)

//export NetworkMonitorStart
func NetworkMonitorStart() int {
	if atomic.CompareAndSwapInt32(&started, 0, 1) {
		// Seed baseline counters so the first delta is not a huge boot value.
		recv, sent := sample()
		atomic.StoreUint64(&lastRecv, recv)
		atomic.StoreUint64(&lastSent, sent)
		go sampleLoop()
	}
	return 0
}

//export NetworkMonitorStop
func NetworkMonitorStop() int {
	atomic.StoreInt32(&started, 0)
	return 0
}

//export NetworkGetTotalRecv
func NetworkGetTotalRecv() uint64 { return atomic.LoadUint64(&lastRecv) }

//export NetworkGetTotalSent
func NetworkGetTotalSent() uint64 { return atomic.LoadUint64(&lastSent) }

//export NetworkGetRecvSpeed
func NetworkGetRecvSpeed() uint64 { return atomic.LoadUint64(&deltaRecv) }

//export NetworkGetSentSpeed
func NetworkGetSentSpeed() uint64 { return atomic.LoadUint64(&deltaSent) }

func sampleLoop() {
	for atomic.LoadInt32(&started) == 1 {
		recv, sent := sample()
		r := recv - atomic.LoadUint64(&lastRecv)
		s := sent - atomic.LoadUint64(&lastSent)
		atomic.StoreUint64(&lastRecv, recv)
		atomic.StoreUint64(&lastSent, sent)
		atomic.StoreUint64(&deltaRecv, r)
		atomic.StoreUint64(&deltaSent, s)
		time.Sleep(time.Second)
	}
}

func sample() (uint64, uint64) {
	counters, err := net.IOCounters(true)
	if err != nil {
		return 0, 0
	}
	var recv, sent uint64
	for _, c := range counters {
		// Skip loopback to reflect real network traffic.
		if strings.Contains(strings.ToLower(c.Name), "loopback") {
			continue
		}
		recv += c.BytesRecv
		sent += c.BytesSent
	}
	return recv, sent
}

func main() {}
