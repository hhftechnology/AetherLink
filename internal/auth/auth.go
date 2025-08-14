package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type TokenManager struct {
	secretKey     []byte
	issuer        string
	enabled       bool
	apiKeys       map[string]*APIKey
	allowedIPs    map[string]bool
	rateLimiter   *RateLimiter
	mutex         sync.RWMutex
}

type APIKey struct {
	Key         string    `json:"key"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	LastUsed    time.Time `json:"last_used"`
	Enabled     bool      `json:"enabled"`
	IPWhitelist []string  `json:"ip_whitelist,omitempty"`
}

type RateLimiter struct {
	requests map[string][]time.Time
	limit    int
	window   time.Duration
	mutex    sync.RWMutex
}

type Claims struct {
	TunnelID  string `json:"tunnel_id"`
	ClientIP  string `json:"client_ip,omitempty"`
	Subdomain string `json:"subdomain,omitempty"`
	APIKeyID  string `json:"api_key_id,omitempty"`
	jwt.RegisteredClaims
}

func NewTokenManager(secretKey string, issuer string, enabled bool) *TokenManager {
	var key []byte
	if secretKey == "" {
		// Generate a random secret key if none provided
		key = make([]byte, 32)
		rand.Read(key)
	} else {
		// Use provided secret key (hash it for consistent length)
		hash := sha256.Sum256([]byte(secretKey))
		key = hash[:]
	}

	return &TokenManager{
		secretKey:   key,
		issuer:      issuer,
		enabled:     enabled,
		apiKeys:     make(map[string]*APIKey),
		allowedIPs:  make(map[string]bool),
		rateLimiter: NewRateLimiter(10, time.Minute), // 10 requests per minute default
	}
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}
}

func (rl *RateLimiter) IsAllowed(clientIP string) bool {
	rl.mutex.Lock()
	defer rl.mutex.Unlock()

	now := time.Now()
	cutoff := now.Add(-rl.window)

	// Clean old requests
	if requests, exists := rl.requests[clientIP]; exists {
		validRequests := make([]time.Time, 0)
		for _, reqTime := range requests {
			if reqTime.After(cutoff) {
				validRequests = append(validRequests, reqTime)
			}
		}
		rl.requests[clientIP] = validRequests
	}

	// Check if under limit
	if len(rl.requests[clientIP]) >= rl.limit {
		return false
	}

	// Add current request
	rl.requests[clientIP] = append(rl.requests[clientIP], now)
	return true
}

func (tm *TokenManager) IsEnabled() bool {
	return tm.enabled
}

// AddAPIKey adds a new API key for client authentication
func (tm *TokenManager) AddAPIKey(name, description string, ipWhitelist []string) (*APIKey, error) {
	tm.mutex.Lock()
	defer tm.mutex.Unlock()

	key := generateAPIKey()
	apiKey := &APIKey{
		Key:         key,
		Name:        name,
		Description: description,
		CreatedAt:   time.Now(),
		Enabled:     true,
		IPWhitelist: ipWhitelist,
	}

	tm.apiKeys[key] = apiKey
	return apiKey, nil
}

// ValidateAPIKey validates client API key before tunnel creation
func (tm *TokenManager) ValidateAPIKey(apiKey, clientIP string) error {
	if !tm.enabled {
		return nil
	}

	if apiKey == "" {
		return fmt.Errorf("API key required")
	}

	tm.mutex.RLock()
	key, exists := tm.apiKeys[apiKey]
	tm.mutex.RUnlock()

	if !exists {
		return fmt.Errorf("invalid API key")
	}

	if !key.Enabled {
		return fmt.Errorf("API key disabled")
	}

	// Check IP whitelist if configured
	if len(key.IPWhitelist) > 0 {
		allowed := false
		clientIPAddr := extractIP(clientIP)
		for _, allowedIP := range key.IPWhitelist {
			if clientIPAddr == allowedIP || isIPInCIDR(clientIPAddr, allowedIP) {
				allowed = true
				break
			}
		}
		if !allowed {
			return fmt.Errorf("IP %s not in whitelist for this API key", clientIPAddr)
		}
	}

	// Check global IP whitelist
	if len(tm.allowedIPs) > 0 {
		clientIPAddr := extractIP(clientIP)
		if !tm.allowedIPs[clientIPAddr] && !tm.isIPInAllowedCIDRs(clientIPAddr) {
			return fmt.Errorf("IP %s not in global whitelist", clientIPAddr)
		}
	}

	// Rate limiting
	if !tm.rateLimiter.IsAllowed(extractIP(clientIP)) {
		return fmt.Errorf("rate limit exceeded for IP %s", extractIP(clientIP))
	}

	// Update last used
	tm.mutex.Lock()
	key.LastUsed = time.Now()
	tm.mutex.Unlock()

	return nil
}

// SetGlobalIPWhitelist sets IPs that are globally allowed
func (tm *TokenManager) SetGlobalIPWhitelist(ips []string) {
	tm.mutex.Lock()
	defer tm.mutex.Unlock()

	tm.allowedIPs = make(map[string]bool)
	for _, ip := range ips {
		tm.allowedIPs[ip] = true
	}
}

func (tm *TokenManager) isIPInAllowedCIDRs(ip string) bool {
	for allowedIP := range tm.allowedIPs {
		if isIPInCIDR(ip, allowedIP) {
			return true
		}
	}
	return false
}

func (tm *TokenManager) GenerateToken(tunnelID, clientIP, subdomain, apiKeyID string) (string, error) {
	if !tm.enabled {
		return "", nil
	}

	now := time.Now()
	claims := Claims{
		TunnelID:  tunnelID,
		ClientIP:  clientIP,
		Subdomain: subdomain,
		APIKeyID:  apiKeyID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tm.issuer,
			Subject:   tunnelID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(24 * time.Hour)), // 24 hour expiry
			NotBefore: jwt.NewNumericDate(now),
			ID:        generateJTI(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(tm.secretKey)
}

func (tm *TokenManager) ValidateToken(tokenString string) (*Claims, error) {
	if !tm.enabled {
		return nil, nil
	}

	if tokenString == "" {
		return nil, fmt.Errorf("no token provided")
	}

	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		// Validate signing method
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return tm.secretKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("token validation failed: %v", err)
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}

	// Additional validation
	if claims.Issuer != tm.issuer {
		return nil, fmt.Errorf("invalid token issuer")
	}

	return claims, nil
}

func (tm *TokenManager) RefreshToken(oldTokenString string) (string, error) {
	if !tm.enabled {
		return "", nil
	}

	claims, err := tm.ValidateToken(oldTokenString)
	if err != nil {
		return "", fmt.Errorf("cannot refresh invalid token: %v", err)
	}

	// Generate new token with same claims but updated timestamps
	return tm.GenerateToken(claims.TunnelID, claims.ClientIP, claims.Subdomain, claims.APIKeyID)
}

// RemoveAPIKey removes an API key
func (tm *TokenManager) RemoveAPIKey(apiKey string) error {
	tm.mutex.Lock()
	defer tm.mutex.Unlock()

	if _, exists := tm.apiKeys[apiKey]; !exists {
		return fmt.Errorf("API key not found")
	}

	delete(tm.apiKeys, apiKey)
	return nil
}

// ListAPIKeys returns all API keys (without the actual key values)
func (tm *TokenManager) ListAPIKeys() []*APIKey {
	tm.mutex.RLock()
	defer tm.mutex.RUnlock()

	keys := make([]*APIKey, 0, len(tm.apiKeys))
	for _, key := range tm.apiKeys {
		// Return copy without the actual key
		keyCopy := *key
		keyCopy.Key = "***" // Hide actual key
		keys = append(keys, &keyCopy)
	}
	return keys
}

// Helper functions
func generateAPIKey() string {
	bytes := make([]byte, 32)
	rand.Read(bytes)
	return "ak_" + hex.EncodeToString(bytes)
}

func generateJTI() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func extractIP(addr string) string {
	if ip := net.ParseIP(addr); ip != nil {
		return ip.String()
	}
	if host, _, err := net.SplitHostPort(addr); err == nil {
		return host
	}
	return addr
}

func isIPInCIDR(ip, cidr string) bool {
	if !strings.Contains(cidr, "/") {
		return ip == cidr
	}
	
	_, ipNet, err := net.ParseCIDR(cidr)
	if err != nil {
		return false
	}
	
	ipAddr := net.ParseIP(ip)
	if ipAddr == nil {
		return false
	}
	
	return ipNet.Contains(ipAddr)
}

// GetClientIP helper function to extract client IP from request
func GetClientIP(remoteAddr, xForwardedFor, xRealIP string) string {
	if xRealIP != "" {
		return extractIP(xRealIP)
	}
	if xForwardedFor != "" {
		// Take the first IP from X-Forwarded-For
		ips := strings.Split(xForwardedFor, ",")
		return extractIP(strings.TrimSpace(ips[0]))
	}
	return extractIP(remoteAddr)
}

// ValidateAPIKeyConstantTime performs constant-time comparison of API keys
func (tm *TokenManager) ValidateAPIKeyConstantTime(provided, stored string) bool {
	return subtle.ConstantTimeCompare([]byte(provided), []byte(stored)) == 1
}