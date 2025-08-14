package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/hhftechnology/AetherLink/internal/auth"
	"github.com/hhftechnology/AetherLink/internal/server"
)

var (
	address       = flag.String("address", "127.0.0.1", "Address to bind to")
	port          = flag.String("port", "8080", "Port to listen on")
	domain        = flag.String("domain", "", "Domain for tunnel endpoints (e.g., tunnel.example.com)")
	secure        = flag.Bool("secure", false, "Enable HTTPS mode")
	authToken     = flag.String("auth-token", "", "Authentication token secret (optional)")
	authEnable    = flag.Bool("auth", false, "Enable token-based authentication")
	issuer        = flag.String("issuer", "aetherlink-server", "Token issuer name")
	version       = flag.Bool("version", false, "Show version information")
	createAPIKey  = flag.String("create-api-key", "", "Create an API key with the given name")
	ipWhitelist   = flag.String("ip-whitelist", "", "Comma-separated list of allowed IPs (optional)")
	showKeys      = flag.Bool("list-keys", false, "List all API keys")
	adminMode     = flag.Bool("admin", false, "Run in admin mode (for key management)")
)

const VERSION = "1.1.0"

func main() {
	flag.Parse()

	if *version {
		fmt.Printf("AetherLink Server v%s\n", VERSION)
		fmt.Println("A secure tunneling solution for exposing local services")
		return
	}

	// Initialize token manager
	var tokenManager *auth.TokenManager
	if *authEnable || *authToken != "" {
		secret := *authToken
		if secret == "" {
			// Try to get from environment variable
			secret = os.Getenv("AETHERLINK_AUTH_SECRET")
		}
		
		tokenManager = auth.NewTokenManager(secret, *issuer, true)
		log.Printf("Authentication enabled with issuer: %s", *issuer)
		
		if secret == "" {
			log.Println("WARNING: No authentication secret provided, using random key (clients won't persist across restarts)")
		}
	} else {
		tokenManager = auth.NewTokenManager("", *issuer, false)
		log.Println("Authentication disabled - server accepts all clients")
	}

	// Handle admin operations
	if *adminMode || *createAPIKey != "" || *showKeys {
		handleAdminOperations(tokenManager)
		return
	}

	// Print startup information
	log.Printf("Starting AetherLink Server v%s", VERSION)
	log.Printf("Listening on %s:%s", *address, *port)
	log.Printf("Tunnel port: 62322")
	
	if *domain != "" {
		schema := "http"
		if *secure {
			schema = "https"
		}
		log.Printf("Domain: %s://*.%s", schema, *domain)
	} else {
		log.Printf("Using path-based routing (no domain configured)")
	}

	if *secure {
		log.Printf("HTTPS mode enabled")
	}

	if tokenManager.IsEnabled() {
		log.Printf("🔐 Authentication is ENABLED")
		log.Printf("   - Clients must provide valid API keys")
		log.Printf("   - Use --create-api-key to generate client keys")
		log.Printf("   - Admin API available at /api/admin/*")
	} else {
		log.Printf("⚠️  Authentication is DISABLED")
		log.Printf("   - Any client can create tunnels")
		log.Printf("   - Enable with --auth flag for production")
	}

	// Create and start server
	srv := server.NewServer(*address, *port, *domain, *secure, tokenManager)
	
	log.Printf("Server ready! Visit http://%s:%s for more information", *address, *port)
	if tokenManager.IsEnabled() {
		log.Printf("📚 Documentation: Use API keys for secure client access")
	}
	
	log.Fatal(srv.ListenAndServe())
}

func handleAdminOperations(tokenManager *auth.TokenManager) {
	if !tokenManager.IsEnabled() {
		log.Fatal("Authentication must be enabled for admin operations. Use --auth flag.")
	}

	if *createAPIKey != "" {
		createAPIKeyCmd(tokenManager, *createAPIKey)
		return
	}

	if *showKeys {
		listAPIKeysCmd(tokenManager)
		return
	}

	// Interactive admin mode
	fmt.Println("AetherLink Admin Mode")
	fmt.Println("Available commands:")
	fmt.Println("  --create-api-key <name>  Create a new API key")
	fmt.Println("  --list-keys              List all API keys")
	fmt.Println("  --help                   Show help")
}

func createAPIKeyCmd(tokenManager *auth.TokenManager, name string) {
	var ipWhitelistArray []string
	if *ipWhitelist != "" {
		ipWhitelistArray = strings.Split(*ipWhitelist, ",")
		for i, ip := range ipWhitelistArray {
			ipWhitelistArray[i] = strings.TrimSpace(ip)
		}
	}

	apiKey, err := tokenManager.AddAPIKey(name, "Generated via CLI", ipWhitelistArray)
	if err != nil {
		log.Fatalf("Failed to create API key: %v", err)
	}

	fmt.Printf("✅ API Key created successfully!\n")
	fmt.Printf("   Name: %s\n", apiKey.Name)
	fmt.Printf("   Key:  %s\n", apiKey.Key)
	fmt.Printf("   Created: %s\n", apiKey.CreatedAt.Format("2006-01-02 15:04:05"))
	
	if len(ipWhitelistArray) > 0 {
		fmt.Printf("   IP Whitelist: %v\n", ipWhitelistArray)
	}
	
	fmt.Printf("\n🔐 Client Usage:\n")
	fmt.Printf("   ./aetherlink-client \\\n")
	fmt.Printf("     --server=https://your-domain.com \\\n")
	fmt.Printf("     --port=3000 \\\n")
	fmt.Printf("     --api-key=%s\n", apiKey.Key)
	
	fmt.Printf("\n💡 Or use Authorization header:\n")
	fmt.Printf("   curl -H \"Authorization: Bearer %s\" \\\n", apiKey.Key)
	fmt.Printf("        https://your-domain.com/?new\n")
}

func listAPIKeysCmd(tokenManager *auth.TokenManager) {
	keys := tokenManager.ListAPIKeys()
	
	if len(keys) == 0 {
		fmt.Println("No API keys found.")
		return
	}

	fmt.Printf("API Keys (%d total):\n", len(keys))
	fmt.Println("┌─────────────────────────┬─────────────────────┬─────────────────────┬─────────┐")
	fmt.Println("│ Name                    │ Created             │ Last Used           │ Status  │")
	fmt.Println("├─────────────────────────┼─────────────────────┼─────────────────────┼─────────┤")
	
	for _, key := range keys {
		lastUsed := "Never"
		if !key.LastUsed.IsZero() {
			lastUsed = key.LastUsed.Format("2006-01-02 15:04")
		}
		
		status := "Enabled"
		if !key.Enabled {
			status = "Disabled"
		}
		
		fmt.Printf("│ %-23s │ %-19s │ %-19s │ %-7s │\n",
			truncateString(key.Name, 23),
			key.CreatedAt.Format("2006-01-02 15:04"),
			lastUsed,
			status)
	}
	fmt.Println("└─────────────────────────┴─────────────────────┴─────────────────────┴─────────┘")
}

func truncateString(s string, length int) string {
	if len(s) <= length {
		return s
	}
	return s[:length-3] + "..."
}