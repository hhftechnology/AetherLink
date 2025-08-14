package server

import (
	"net/http"
)

type Server struct {
	address string
	port    string
	manager *ClientManager
}

func NewServer(address, port, domain string, secure bool) *Server {
	m := NewClientManager(domain, secure)
	http.HandleFunc("/", m.handler)
	return &Server{
		address: address,
		port:    port,
		manager: m,
	}
}

func (s *Server) ListenAndServe() error {
	return http.ListenAndServe(s.address+":"+s.port, nil)
}