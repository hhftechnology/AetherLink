package main

import (
	"flag"
	"fmt"
	"log"
	"net/url"
	"os"
	"strconv"

	"github.com/hhftechnology/AetherLink/internal/client"
)

var (
	localPort = flag.String("port", "80", "Local port to expose")
	serverURL = flag.String("server", "http://localhost:80", "Server URL")
	subdomain = flag.String("subdomain", "", "Request a specific subdomain (only if server has --domain set)")
	apiKey    = flag.String("api-key", "", "API key for authentication (required if server has auth enabled)")
	version   = flag.Bool("version", false, "Show version information")
)

const VERSION = "1.1.0"

func main() {
	flag.Parse()

	if *version {
		fmt.Printf("AetherLink Client v%s\n", VERSION)
		fmt.Println("A secure tunneling solution for exposing local services")
		return
	}

	u, err := url.Parse(*serverURL)
	if err != nil {
		log.Fatal(err)
	}

	path := "/?new"
	if *subdomain != "" {
		path = "/" + *subdomain
	}

	// Get API key from environment if not provided via flag
	clientAPIKey := *apiKey
	if clientAPIKey == "" {
		clientAPIKey = os.Getenv("AETHERLINK_API_KEY")
	}

	fmt.Printf("Requesting tunnel from %s%s...\n", *serverURL, path)
	if clientAPIKey != "" {
		fmt.Printf("🔐 Using API key authentication\n")
	} else {
		fmt.Printf("⚠️  No API key provided (server may require authentication)\n")
	}
	
	info, err := client.RequestTunnel(*serverURL + path, clientAPIKey)
	if err != nil {
		if clientAPIKey == "" {
			fmt.Printf("\n❌ Failed to create tunnel: %v\n", err)
			fmt.Printf("\n💡 If the server requires authentication, provide an API key:\n")
			fmt.Printf("   ./aetherlink-client --api-key=<your-key> --server=%s --port=%s\n", *serverURL, *localPort)
			fmt.Printf("   OR set environment variable: export AETHERLINK_API_KEY=<your-key>\n")
		} else {
			fmt.Printf("\n❌ Authentication failed: %v\n", err)
			fmt.Printf("\n💡 Check your API key or contact your server administrator\n")
		}
		log.Fatal(err)
	}

	id := info.ID
	tcpPort := info.Port
	maxConn := info.MaxConnCount
	tunnelURL := info.URL
	authRequired := info.AuthRequired
	token := info.Token

	if tunnelURL == "" {
		tunnelURL = u.Scheme + "://" + u.Host + "/" + id
	}

	fmt.Printf("✅ Tunnel created successfully!\n")
	fmt.Printf("  Tunnel ID: %s\n", id)
	fmt.Printf("  Public URL: %s\n", tunnelURL)
	fmt.Printf("  Local port: %s\n", *localPort)
	fmt.Printf("  Max connections: %d\n", maxConn)
	
	if authRequired {
		fmt.Printf("  Authentication: ✅ Required (using API key)\n")
		if token != "" {
			fmt.Printf("  Access token: Received and ready\n")
		}
	} else {
		fmt.Printf("  Authentication: ⚠️  Disabled on server\n")
	}

	fmt.Printf("\nStarting tunnel connections...\n")

	localAddr := "127.0.0.1:" + *localPort
	tcpAddr := u.Hostname() + ":" + strconv.Itoa(tcpPort)

	// Start multiple connections for load balancing
	for i := 0; i < maxConn; i++ {
		go func(connNum int) {
			fmt.Printf("Starting connection %d to %s\n", connNum+1, tcpAddr)
			client.MaintainConnection(tcpAddr, localAddr, id, token)
		}(i)
	}

	fmt.Printf("\n🚀 Tunnel is now active! Press Ctrl+C to stop.\n")
	fmt.Printf("Forward traffic from %s to %s\n", tunnelURL, localAddr)
	
	if authRequired {
		fmt.Printf("🔐 Tunnel is secured with API key authentication\n")
	}

	select {} // block forever
}