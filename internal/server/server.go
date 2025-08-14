package server

import (
	"net/http"

	"github.com/hhftechnology/AetherLink/internal/auth"
)

type Server struct {
	address string
	port    string
	manager *ClientManager
}

func NewServer(address, port, domain string, secure bool, tokenManager *auth.TokenManager) *Server {
	m := NewClientManager(domain, secure, tokenManager)
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