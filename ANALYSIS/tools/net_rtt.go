package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"sort"
	"time"
)

var (
	mode       = flag.String("mode", "", "server or client")
	network    = flag.String("network", "tcp", "tcp or udp")
	addr       = flag.String("addr", "", "listen or destination address")
	count      = flag.Int("count", 10000, "number of request/reply exchanges")
	payloadLen = flag.Int("payload", 64, "payload bytes")
	timeout    = flag.Duration("timeout", 120*time.Second, "server lifetime or per-I/O client timeout")
)

func main() {
	flag.Parse()
	if *addr == "" || *count <= 0 || *payloadLen < 8 {
		fatalf("addr, positive count, and payload >= 8 are required")
	}
	var err error
	switch {
	case *mode == "server" && *network == "tcp":
		err = serveTCP()
	case *mode == "server" && *network == "udp":
		err = serveUDP()
	case *mode == "client" && (*network == "tcp" || *network == "udp"):
		err = runClient()
	default:
		err = fmt.Errorf("unsupported mode/network %q/%q", *mode, *network)
	}
	if err != nil {
		fatalf("%v", err)
	}
}

func serveTCP() error {
	listener, err := net.Listen("tcp", *addr)
	if err != nil {
		return err
	}
	defer listener.Close()
	fmt.Printf("READY network=tcp addr=%s\n", listener.Addr())
	deadline := time.Now().Add(*timeout)
	if tcp, ok := listener.(*net.TCPListener); ok {
		_ = tcp.SetDeadline(deadline)
	}
	conn, err := listener.Accept()
	if err != nil {
		return err
	}
	defer conn.Close()
	_ = conn.SetDeadline(deadline)
	buf := make([]byte, *payloadLen)
	for i := 0; i < *count; i++ {
		if _, err := io.ReadFull(conn, buf); err != nil {
			return fmt.Errorf("receive exchange %d: %w", i, err)
		}
		if err := writeFull(conn, buf); err != nil {
			return fmt.Errorf("reply exchange %d: %w", i, err)
		}
	}
	fmt.Printf("SERVER_PASS network=tcp exchanges=%d\n", *count)
	return nil
}

func serveUDP() error {
	udpAddr, err := net.ResolveUDPAddr("udp", *addr)
	if err != nil {
		return err
	}
	conn, err := net.ListenUDP("udp", udpAddr)
	if err != nil {
		return err
	}
	defer conn.Close()
	fmt.Printf("READY network=udp addr=%s\n", conn.LocalAddr())
	_ = conn.SetDeadline(time.Now().Add(*timeout))
	buf := make([]byte, *payloadLen)
	for i := 0; i < *count; i++ {
		n, peer, err := conn.ReadFromUDP(buf)
		if err != nil {
			return fmt.Errorf("receive exchange %d: %w", i, err)
		}
		if n != *payloadLen {
			return fmt.Errorf("exchange %d payload length %d, want %d", i, n, *payloadLen)
		}
		if _, err := conn.WriteToUDP(buf[:n], peer); err != nil {
			return fmt.Errorf("reply exchange %d: %w", i, err)
		}
	}
	fmt.Printf("SERVER_PASS network=udp exchanges=%d\n", *count)
	return nil
}

func runClient() error {
	conn, err := net.DialTimeout(*network, *addr, *timeout)
	if err != nil {
		return err
	}
	defer conn.Close()
	sent := make([]byte, *payloadLen)
	received := make([]byte, *payloadLen)
	latencies := make([]time.Duration, 0, *count)
	started := time.Now()
	for i := 0; i < *count; i++ {
		for j := range sent {
			sent[j] = byte(i + j)
		}
		_ = conn.SetDeadline(time.Now().Add(*timeout))
		start := time.Now()
		if err := writeFull(conn, sent); err != nil {
			return fmt.Errorf("send exchange %d: %w", i, err)
		}
		if _, err := io.ReadFull(conn, received); err != nil {
			return fmt.Errorf("receive exchange %d: %w", i, err)
		}
		latencies = append(latencies, time.Since(start))
		if !bytes.Equal(sent, received) {
			return fmt.Errorf("exchange %d payload mismatch", i)
		}
	}
	printStats(latencies, time.Since(started))
	return nil
}

func writeFull(writer io.Writer, payload []byte) error {
	for len(payload) > 0 {
		n, err := writer.Write(payload)
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrUnexpectedEOF
		}
		payload = payload[n:]
	}
	return nil
}

func printStats(values []time.Duration, elapsed time.Duration) {
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	var total time.Duration
	for _, value := range values {
		total += value
	}
	percentile := func(percent int) time.Duration {
		index := (len(values)*percent + 99) / 100
		if index < 1 {
			index = 1
		}
		return values[index-1]
	}
	fmt.Printf("CLIENT_PASS network=%s exchanges=%d loss=0 elapsed_ms=%.3f exchanges_per_sec=%.2f messages_per_sec=%.2f min_us=%.3f avg_us=%.3f p50_us=%.3f p95_us=%.3f p99_us=%.3f max_us=%.3f\n",
		*network, len(values), float64(elapsed)/float64(time.Millisecond),
		float64(len(values))/elapsed.Seconds(), float64(2*len(values))/elapsed.Seconds(),
		float64(values[0])/float64(time.Microsecond),
		float64(total)/float64(len(values))/float64(time.Microsecond),
		float64(percentile(50))/float64(time.Microsecond),
		float64(percentile(95))/float64(time.Microsecond),
		float64(percentile(99))/float64(time.Microsecond),
		float64(values[len(values)-1])/float64(time.Microsecond))
}

func fatalf(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "net-rtt: "+format+"\n", args...)
	os.Exit(1)
}
