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

	"github.com/hhftechnology/AetherLink/internal/auth"
)

const tunnelPort = 62322

var idRegex = regexp.MustCompile(`^(?:[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]|[a-z0-9]{4,63})$`)

type Client struct {
	id         string
	port       int
	maxConn    int
	conns      []net.Conn
	next       int
	mutex      sync.Mutex
	token      string
	createdAt  time.Time
	lastAccess time.Time
}

func (c *Client) addConn(conn net.Conn) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.conns = append(c.conns, conn)
	c.lastAccess = time.Now()
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

func (c *Client) updateLastAccess() {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	c.lastAccess = time.Now()
}

func (c *Client) handleRequest(w http.ResponseWriter, r *http.Request) {
	c.updateLastAccess()
	
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
	c.updateLastAccess()
	
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
	tokenManager   *auth.TokenManager
}

func NewClientManager(domain string, secure bool, tokenManager *auth.TokenManager) *ClientManager {
	rand.Seed(time.Now().UnixNano())
	m := &ClientManager{
		domain:       domain,
		landing:      "https://AetherLink.github.io/www/",
		secure:       secure,
		tokenManager: tokenManager,
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
	
	// Start cleanup routine for expired tokens and inactive clients
	go m.cleanupRoutine()
	
	return m
}

func (m *ClientManager) handleTunnelConn(conn net.Conn) {
	br := bufio.NewReader(conn)
	
	// Read tunnel ID
	id, err := br.ReadString('\n')
	if err != nil {
		log.Printf("Error reading tunnel ID: %v", err)
		conn.Close()
		return
	}
	id = strings.TrimSpace(id)
	
	// Read authentication token if auth is enabled
	var token string
	if m.tokenManager.IsEnabled() {
		tokenLine, err := br.ReadString('\n')
		if err != nil {
			log.Printf("Error reading auth token: %v", err)
			conn.Close()
			return
		}
		token = strings.TrimSpace(tokenLine)
		
		// Validate token
		claims, err := m.tokenManager.ValidateToken(token)
		if err != nil {
			log.Printf("Invalid token for tunnel %s: %v", id, err)
			conn.Close()
			return
		}
		
		// Verify token matches tunnel ID
		if claims.TunnelID != id {
			log.Printf("Token tunnel ID mismatch: expected %s, got %s", id, claims.TunnelID)
			conn.Close()
			return
		}
	}
	
	c := m.GetClient(id)
	if c == nil {
		log.Printf("Unknown tunnel ID: %s", id)
		conn.Close()
		return
	}
	
	// Verify token matches stored token if auth is enabled
	if m.tokenManager.IsEnabled() && c.token != token {
		log.Printf("Token mismatch for tunnel %s", id)
		conn.Close()
		return
	}
	
	c.addConn(conn)
}

func (m *ClientManager) cleanupRoutine() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	
	for range ticker.C {
		m.clients.Range(func(key, value interface{}) bool {
			client := value.(*Client)
			
			// Remove clients inactive for more than 1 hour
			if time.Since(client.lastAccess) > time.Hour {
				log.Printf("Removing inactive client: %s", client.id)
				m.clients.Delete(key)
			}
			
			return true
		})
	}
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
		"tunnels":        m.Tunnels(),
		"auth_enabled":   m.tokenManager.IsEnabled(),
		"tunnel_port":    tunnelPort,
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

func (m *ClientManager) NewClient(id string, clientIP string, apiKey string) (map[string]interface{}, error) {
	if m.GetClient(id) != nil {
		return nil, fmt.Errorf("ID %s already exists", id)
	}

	// Validate API key BEFORE creating tunnel (if auth enabled)
	if m.tokenManager.IsEnabled() {
		if err := m.tokenManager.ValidateAPIKey(apiKey, clientIP); err != nil {
			return nil, fmt.Errorf("authentication failed: %v", err)
		}
	}

	// Generate authentication token if enabled
	var token string
	var err error
	if m.tokenManager.IsEnabled() {
		token, err = m.tokenManager.GenerateToken(id, clientIP, id, apiKey)
		if err != nil {
			return nil, fmt.Errorf("failed to generate token: %v", err)
		}
	}

	c := &Client{
		id:         id,
		port:       tunnelPort,
		maxConn:    10,
		token:      token,
		createdAt:  time.Now(),
		lastAccess: time.Now(),
	}

	m.clients.Store(id, c)

	info := map[string]interface{}{
		"id":             id,
		"port":           tunnelPort,
		"max_conn_count": c.maxConn,
		"url":            "",
		"auth_required":  m.tokenManager.IsEnabled(),
	}

	if m.tokenManager.IsEnabled() {
		info["token"] = token
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

	// API endpoints
	if path == "/api/status" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(m.Stats())
		return
	}

	// API Key management endpoints (require admin API key)
	if strings.HasPrefix(path, "/api/admin/") {
		m.handleAdminAPI(w, r)
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
		response := map[string]interface{}{
			"connected_sockets": c.connectedSockets(),
			"created_at":        c.createdAt.Unix(),
			"last_access":       c.lastAccess.Unix(),
		}
		json.NewEncoder(w).Encode(response)
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
		// Extract client IP for token generation and validation
		clientIP := auth.GetClientIP(
			r.RemoteAddr,
			r.Header.Get("X-Forwarded-For"),
			r.Header.Get("X-Real-IP"),
		)

		// Extract API key from request (Authorization header or query parameter)
		apiKey := extractAPIKey(r)

		info, err := m.NewClient(id, clientIP, apiKey)
		if err != nil {
			if strings.Contains(err.Error(), "authentication failed") {
				http.Error(w, err.Error(), http.StatusUnauthorized)
			} else {
				http.Error(w, err.Error(), http.StatusConflict)
			}
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

func (m *ClientManager) handleAdminAPI(w http.ResponseWriter, r *http.Request) {
	// Extract admin API key
	adminKey := extractAPIKey(r)
	if adminKey == "" {
		http.Error(w, "Admin API key required", http.StatusUnauthorized)
		return
	}

	// For now, use a simple admin key validation
	// In production, you might want a separate admin key system
	clientIP := auth.GetClientIP(r.RemoteAddr, r.Header.Get("X-Forwarded-For"), r.Header.Get("X-Real-IP"))
	if err := m.tokenManager.ValidateAPIKey(adminKey, clientIP); err != nil {
		http.Error(w, "Invalid admin API key", http.StatusUnauthorized)
		return
	}

	path := strings.TrimPrefix(r.URL.Path, "/api/admin")

	switch {
	case path == "/keys" && r.Method == "GET":
		m.listAPIKeys(w, r)
	case path == "/keys" && r.Method == "POST":
		m.createAPIKey(w, r)
	case strings.HasPrefix(path, "/keys/") && r.Method == "DELETE":
		keyID := strings.TrimPrefix(path, "/keys/")
		m.deleteAPIKey(w, r, keyID)
	default:
		http.NotFound(w, r)
	}
}

func (m *ClientManager) listAPIKeys(w http.ResponseWriter, r *http.Request) {
	keys := m.tokenManager.ListAPIKeys()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"api_keys": keys,
	})
}

func (m *ClientManager) createAPIKey(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name        string   `json:"name"`
		Description string   `json:"description"`
		IPWhitelist []string `json:"ip_whitelist,omitempty"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if req.Name == "" {
		http.Error(w, "Name is required", http.StatusBadRequest)
		return
	}

	apiKey, err := m.tokenManager.AddAPIKey(req.Name, req.Description, req.IPWhitelist)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"api_key":     apiKey.Key,
		"name":        apiKey.Name,
		"description": apiKey.Description,
		"created_at":  apiKey.CreatedAt,
	})
}

func (m *ClientManager) deleteAPIKey(w http.ResponseWriter, r *http.Request, keyID string) {
	err := m.tokenManager.RemoveAPIKey(keyID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func extractAPIKey(r *http.Request) string {
	// Try Authorization header first (Bearer token)
	if auth := r.Header.Get("Authorization"); auth != "" {
		if strings.HasPrefix(auth, "Bearer ") {
			return strings.TrimPrefix(auth, "Bearer ")
		}
		if strings.HasPrefix(auth, "ApiKey ") {
			return strings.TrimPrefix(auth, "ApiKey ")
		}
	}

	// Try query parameter
	if key := r.URL.Query().Get("api_key"); key != "" {
		return key
	}

	// Try custom header
	if key := r.Header.Get("X-API-Key"); key != "" {
		return key
	}

	return ""
}