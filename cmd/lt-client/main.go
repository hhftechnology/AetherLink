package main

import (
	"flag"
	"fmt"
	"log"
	"net/url"
	"strconv"

	"github.com/hhftechnology/AetherLink/internal/client"
)

var (
	localPort = flag.String("port", "80", "Local port to expose")
	serverURL = flag.String("server", "http://localhost:80", "Server URL")
	subdomain = flag.String("subdomain", "", "Request a specific subdomain (only if server has --domain set)")
)

func main() {
	flag.Parse()

	u, err := url.Parse(*serverURL)
	if err != nil {
		log.Fatal(err)
	}

	path := "/?new"
	if *subdomain != "" {
		path = "/" + *subdomain
	}

	info, err := client.RequestTunnel(*serverURL + path)
	if err != nil {
		log.Fatal(err)
	}

	id := info["id"].(string)
	tcpPort := int(info["port"].(float64))
	maxConn := int(info["max_conn_count"].(float64))
	tunnelURL := info["url"].(string)

	if tunnelURL == "" {
		tunnelURL = u.Scheme + "://" + u.Host + "/" + id
	}

	fmt.Printf("Your public URL is: %s\n", tunnelURL)

	localAddr := "127.0.0.1:" + *localPort
	tcpAddr := u.Hostname() + ":" + strconv.Itoa(tcpPort)

	for i := 0; i < maxConn; i++ {
		go client.MaintainConnection(tcpAddr, localAddr)
	}

	select {} // block forever
}