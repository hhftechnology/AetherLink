package server

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net"
	"net/http"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"
)

const tunnelPort = 62322

var idRegex = regexp.MustCompile(`^(?:[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]|[a-z0-9]{4,63})$`)

type Client struct {
	id      string
	port    int
	maxConn int
	conns   []net.Conn
	next    int
	mutex   sync.Mutex
}

func (c *Client) addConn(conn net.Conn) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.conns = append(c.conns, conn)
}

func (c *Client) removeConn(conn net.Conn) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	for i, cn := range c.conns {
		if cn == conn {
			c.conns = append(c.conns[:i], c.conns[i+1:]...)
			break
		}
	}
	conn.Close()
}

func (c *Client) connectedSockets() int {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	return len(c.conns)
}

func (c *Client) handleRequest(w http.ResponseWriter, r *http.Request) {
	c.mutex.Lock()
	if len(c.conns) == 0 {
		c.mutex.Unlock()
		http.Error(w, "No available connections", http.StatusBadGateway)
		return
	}
	conn := c.conns[c.next]
	c.next = (c.next + 1) % len(c.conns)
	c.mutex.Unlock()

	if err := r.Write(conn); err != nil {
		c.removeConn(conn)
		http.Error(w, "Proxy error", http.StatusBadGateway)
		return
	}

	resp, err := http.ReadResponse(bufio.NewReader(conn), r)
	if err != nil {
		c.removeConn(conn)
		http.Error(w, "Proxy error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func (c *Client) handleUpgrade(w http.ResponseWriter, r *http.Request) {
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Webserver doesn't support hijacking", http.StatusInternalServerError)
		return
	}
	netConn, _, err := hj.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer netConn.Close()

	c.mutex.Lock()
	if len(c.conns) == 0 {
		c.mutex.Unlock()
		return
	}
	conn := c.conns[c.next]
	c.next = (c.next + 1) % len(c.conns)
	c.mutex.Unlock()

	if err := r.Write(conn); err != nil {
		c.removeConn(conn)
		return
	}

	go io.Copy(conn, netConn)
	io.Copy(netConn, conn)
}

type ClientManager struct {
	clients        sync.Map // map[string]*Client
	domain         string
	landing        string
	secure         bool
	tunnelListener net.Listener
}

func NewClientManager(domain string, secure bool) *ClientManager {
	rand.Seed(time.Now().UnixNano())
	m := &ClientManager{
		domain:  domain,
		landing: "https://AetherLink.github.io/www/",
		secure:  secure,
	}
	var err error
	m.tunnelListener, err = net.Listen("tcp", "0.0.0.0:"+fmt.Sprintf("%d", tunnelPort))
	if err != nil {
		log.Fatalf("Failed to listen on tunnel port: %v", err)
	}
	go func() {
		for {
			conn, err := m.tunnelListener.Accept()
			if err != nil {
				log.Printf("Tunnel listener error: %v", err)
				break
			}
			go m.handleTunnelConn(conn)
		}
	}()
	return m
}

func (m *ClientManager) handleTunnelConn(conn net.Conn) {
	br := bufio.NewReader(conn)
	id, err := br.ReadString('\n')
	if err != nil {
		log.Printf("Error reading tunnel ID: %v", err)
		conn.Close()
		return
	}
	id = strings.TrimSpace(id)
	c := m.GetClient(id)
	if c == nil {
		log.Printf("Unknown tunnel ID: %s", id)
		conn.Close()
		return
	}
	c.addConn(conn)
}

func (m *ClientManager) Tunnels() int {
	count := 0
	m.clients.Range(func(_, _ interface{}) bool {
		count++
		return true
	})
	return count
}

func (m *ClientManager) Stats() map[string]interface{} {
	mem := new(runtime.MemStats)
	runtime.ReadMemStats(mem)
	return map[string]interface{}{
		"tunnels": m.Tunnels(),
		"mem": map[string]uint64{
			"alloc":      mem.Alloc,
			"totalAlloc": mem.TotalAlloc,
			"sys":        mem.Sys,
			"heapAlloc":  mem.HeapAlloc,
		},
	}
}

func (m *ClientManager) GetClient(id string) *Client {
	v, ok := m.clients.Load(id)
	if !ok {
		return nil
	}
	return v.(*Client)
}

func (m *ClientManager) NewClient(id string) (map[string]interface{}, error) {
	if m.GetClient(id) != nil {
		return nil, fmt.Errorf("ID %s already exists", id)
	}

	c := &Client{
		id:      id,
		port:    tunnelPort,
		maxConn: 10,
	}

	m.clients.Store(id, c)

	info := map[string]interface{}{
		"id":             id,
		"port":           tunnelPort,
		"max_conn_count": c.maxConn,
		"url":            "",
	}

	if m.domain != "" {
		schema := "http"
		if m.secure {
			schema = "https"
		}
		info["url"] = fmt.Sprintf("%s://%s.%s", schema, id, m.domain)
	}

	return info, nil
}

func (m *ClientManager) GetClientIdFromHostname(host string) string {
	if m.domain == "" {
		return ""
	}
	h := strings.TrimSuffix(host, "."+m.domain)
	if h == host {
		return ""
	}
	return h
}

func randomID() string {
	adjectives := []string{"angry", "brave", "calm", "delightful", "eager", "fierce", "gentle", "happy", "jolly", "kind", "lively", "nice", "proud", "silly", "thankful", "victorious", "witty", "zealous"}
	colors := []string{"red", "orange", "yellow", "green", "blue", "purple", "pink", "brown", "grey", "black"}
	animals := []string{"tiger", "lion", "elephant", "monkey", "panda", "koala", "giraffe", "zebra", "wolf", "fox", "bear", "rabbit"}

	return adjectives[rand.Intn(len(adjectives))] + "-" + colors[rand.Intn(len(colors))] + "-" + animals[rand.Intn(len(animals))]
}

func (m *ClientManager) handler(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path

	if path == "/api/status" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(m.Stats())
		return
	}

	if strings.HasPrefix(path, "/api/tunnels/") && strings.HasSuffix(path, "/status") {
		id := strings.TrimPrefix(path, "/api/tunnels/")
		id = strings.TrimSuffix(id, "/status")
		c := m.GetClient(id)
		if c == nil {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]int{"connected_sockets": c.connectedSockets()})
		return
	}

	id := ""
	customAllowed := m.domain != ""

	if path == "/" {
		if _, ok := r.URL.Query()["new"]; ok {
			id = randomID()
		} else {
			http.Redirect(w, r, m.landing, http.StatusFound)
			return
		}
	} else if customAllowed {
		parts := strings.Split(strings.TrimPrefix(path, "/"), "/")
		if len(parts) == 1 {
			id = parts[0]
			if len(id) > 63 || !idRegex.MatchString(id) {
				http.Error(w, "Invalid subdomain. Subdomains must be lowercase and between 4 and 63 alphanumeric characters.", http.StatusForbidden)
				return
			}
		} else {
			http.NotFound(w, r)
			return
		}
	}

	if id != "" {
		info, err := m.NewClient(id)
		if err != nil {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(info)
		return
	}

	// proxy
	clientId := ""
	newPath := path
	if m.domain != "" {
		host := strings.Split(r.Host, ":")[0]
		clientId = m.GetClientIdFromHostname(host)
	} else {
		p := strings.TrimPrefix(path, "/")
		parts := strings.Split(p, "/")
		if len(parts) >= 1 && parts[0] != "" {
			clientId = parts[0]
			newPath = "/"
			if len(parts) > 1 {
				newPath += strings.Join(parts[1:], "/")
			}
		}
	}

	if clientId == "" {
		http.NotFound(w, r)
		return
	}

	r.URL.Path = newPath

	c := m.GetClient(clientId)
	if c == nil {
		http.NotFound(w, r)
		return
	}

	if r.Header.Get("Upgrade") == "websocket" {
		c.handleUpgrade(w, r)
	} else {
		c.handleRequest(w, r)
	}
}