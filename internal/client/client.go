package client

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"time"
)

func RequestTunnel(url string) (map[string]interface{}, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("server returned %d", resp.StatusCode)
	}

	var info map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return nil, err
	}

	return info, nil
}

func MaintainConnection(tcpAddr, localAddr, id string) {
	for {
		conn, err := net.Dial("tcp", tcpAddr)
		if err != nil {
			log.Printf("Failed to connect to server: %v", err)
			time.Sleep(time.Second)
			continue
		}
		_, err = conn.Write([]byte(id + "\n"))
		if err != nil {
			log.Printf("Failed to send tunnel ID: %v", err)
			conn.Close()
			time.Sleep(time.Second)
			continue
		}
		HandleConnection(conn, localAddr)
	}
}

func HandleConnection(conn net.Conn, localPort string) {
	defer conn.Close()
	for {
		br := bufio.NewReader(conn)
		req, err := http.ReadRequest(br)
		if err != nil {
			if err != io.EOF {
				log.Printf("Failed to read request: %v", err)
			}
			return
		}

		req.URL.Scheme = "http"
		req.URL.Host = "127.0.0.1:" + localPort

		localConn, err := net.Dial("tcp", req.URL.Host)
		if err != nil {
			log.Printf("Failed to connect to local: %v", err)
			resp := &http.Response{
				StatusCode: http.StatusBadGateway,
				ProtoMajor: 1,
				ProtoMinor: 1,
				Header:     make(http.Header),
				Body:       io.NopCloser(strings.NewReader("Bad Gateway")),
			}
			resp.Write(conn)
			continue
		}

		err = req.Write(localConn)
		if err != nil {
			log.Printf("Failed to write request to local: %v", err)
			localConn.Close()
			continue
		}

		localBR := bufio.NewReader(localConn)
		resp, err := http.ReadResponse(localBR, req)
		if err != nil {
			log.Printf("Failed to read local response: %v", err)
			localConn.Close()
			continue
		}

		if req.Header.Get("Upgrade") == "websocket" && resp.StatusCode == 101 {
			resp.Body.Close()
			resp.Write(conn)
			go io.Copy(localConn, conn)
			io.Copy(conn, localConn)
			localConn.Close()
			return
		} else {
			defer resp.Body.Close()
			resp.Write(conn)
		}

		localConn.Close()
	}
}