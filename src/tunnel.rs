use serde::{Deserialize, Serialize};

/// ALPN protocol identifier for AetherLink tunnels
pub const TUNNEL_ALPN: &[u8] = b"aetherlink/tunnel/1.0.0";

/// Messages exchanged between client and server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TunnelMessage {
    /// Client requests to register a tunnel
    Register {
        domain: String,
        port: u16,
    },
    
    /// Server confirms tunnel registration
    Registered {
        domain: String,
    },
    
    /// Client requests to unregister a tunnel
    Unregister {
        domain: String,
    },
    
    /// Server confirms tunnel unregistration
    Unregistered {
        domain: String,
    },
    
    /// Client requests list of active tunnels
    List,
    
    /// Server responds with list of tunnels
    TunnelList {
        tunnels: Vec<String>,
    },
    
    /// Error response
    Error {
        message: String,
    },
    
    /// HTTP request to be forwarded
    HttpRequest {
        method: String,
        uri: String,
        headers: Vec<(String, String)>,
        body: Vec<u8>,
    },
    
    /// HTTP response from forwarded request
    HttpResponse {
        status: u16,
        headers: Vec<(String, String)>,
        body: Vec<u8>,
    },
}