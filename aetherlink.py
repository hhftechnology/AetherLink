#!/usr/bin/env python3

from __future__ import annotations
import sys
import json
import time
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Dict, Any
from urllib import request
from urllib.error import URLError
import signal
import argparse
import socket
import threading
import os
from contextlib import contextmanager

@dataclass
class TunnelConfig:
    """Configuration for tunnel setup"""
    host: str
    port: str
    local_port: str
    base_url: str = "http://127.0.0.1:2019"
    health_check_interval: int = 5

    @property
    def tunnel_id(self) -> str:
        """Generate unique tunnel identifier"""
        return f"aetherlink-{self.host}-{self.port}"

class ServiceHealth:
    """Health monitoring for services"""
    def __init__(self, host: str, port: int, timeout: int = 30):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.logger = logging.getLogger('ServiceHealth')

    def check(self, service_name: str = "Service") -> bool:
        """Check service availability"""
        self.logger.info(f"Checking {service_name} on {self.host}:{self.port}...")
        start_time = time.time()
        
        while time.time() - start_time < self.timeout:
            try:
                with socket.create_connection((self.host, self.port), timeout=2):
                    self.logger.info(f"{service_name} is available")
                    return True
            except (socket.timeout, socket.error) as e:
                if time.time() - start_time >= self.timeout:
                    self.logger.error(f"{service_name} unavailable: {e}")
                    return False
            time.sleep(1)
        return False

class HTTPClient:
    """HTTP client with retry capability"""
    def __init__(self, base_url: str, timeout: int = 10, max_retries: int = 3):
        self.base_url = base_url
        self.timeout = timeout
        self.max_retries = max_retries
        self.logger = logging.getLogger('HTTPClient')

    def request(self, method: str, endpoint: str, data: Optional[Dict[str, Any]] = None) -> bool:
        """Make HTTP request with retries"""
        headers = {'Content-Type': 'application/json'} if data else {}
        encoded_data = json.dumps(data).encode('utf-8') if data else None

        for attempt in range(self.max_retries):
            try:
                req = request.Request(
                    method=method,
                    url=f"{self.base_url}{endpoint}",
                    headers=headers,
                    data=encoded_data
                )
                with request.urlopen(req, timeout=self.timeout) as response:
                    return response.status == 200
            except Exception as e:
                if attempt == self.max_retries - 1:
                    self.logger.error(f"Request failed after {self.max_retries} attempts: {e}")
                    return False
                time.sleep(1)
        return False

class AetherLink:
    """AetherLink - Secure and reliable tunnel manager"""
    
    def __init__(self, config: TunnelConfig):
        self.config = config
        self.is_running = True
        self.http_client = HTTPClient(config.base_url)
        self._setup_environment()
        self._setup_logging()
        self._setup_signal_handlers()

    def _setup_environment(self) -> None:
        """Initialize required directories"""
        Path('logs').mkdir(exist_ok=True)
        Path('config').mkdir(exist_ok=True)

    def _setup_logging(self) -> None:
        """Configure logging system"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(),
                logging.FileHandler(Path('logs') / 'aetherlink.log')
            ]
        )
        self.logger = logging.getLogger('AetherLink')

    def _setup_signal_handlers(self) -> None:
        """Configure graceful shutdown handlers"""
        signal.signal(signal.SIGINT, self._handle_shutdown)
        signal.signal(signal.SIGTERM, self._handle_shutdown)

    def _create_route_config(self) -> Dict[str, Any]:
        """Generate routing configuration"""
        return {
            "@id": self.config.tunnel_id,
            "match": [{"host": [self.config.host]}],
            "handle": [{
                "handler": "reverse_proxy",
                "upstreams": [{
                    "dial": f"127.0.0.1:{self.config.local_port}"
                }],
                "health_checks": {
                    "active": {
                        "interval": "10s",
                        "timeout": "5s",
                        "uri": "/",
                        "host": self.config.host
                    },
                    "passive": {
                        "fail_duration": "30s",
                        "max_fails": 3
                    }
                },
                "transport": {
                    "protocol": "http",
                    "tls": {},
                    "read_buffer_size": 4096,
                    "write_buffer_size": 4096,
                    "dial_timeout": "10s",
                    "response_header_timeout": "30s",
                    "keep_alive": {
                        "enabled": True,
                        "probe_interval": "30s",
                        "idle_timeout": "120s"
                    }
                }
            }]
        }

    def _handle_shutdown(self, signum: int, frame: Any) -> None:
        """Handle shutdown signals"""
        self.logger.info("Shutdown signal received")
        self.is_running = False

    def _monitor_health(self) -> None:
        """Monitor local service health"""
        health_checker = ServiceHealth('127.0.0.1', int(self.config.local_port))
        while self.is_running:
            if not health_checker.check("Local service"):
                self.logger.error("Local service unresponsive")
            time.sleep(self.config.health_check_interval)

    @contextmanager
    def _tunnel_lifecycle(self) -> bool:
        """Manage tunnel lifecycle"""
        try:
            if not self.create_tunnel():
                raise RuntimeError("Failed to create tunnel")
            yield True
        finally:
            if not self.delete_tunnel():
                self.logger.error("Failed to clean up tunnel")

    def create_tunnel(self) -> bool:
        """Create and configure tunnel"""
        health_checker = ServiceHealth('127.0.0.1', int(self.config.local_port))
        caddy_checker = ServiceHealth('127.0.0.1', 2019)

        if not all([
            health_checker.check("Local service"),
            caddy_checker.check("Caddy admin API")
        ]):
            return False

        self.logger.info(f"Creating tunnel for {self.config.host}:{self.config.port}")
        return self.http_client.request(
            'POST',
            '/config/apps/http/servers/aetherlink/routes',
            self._create_route_config()
        )

    def delete_tunnel(self) -> bool:
        """Remove tunnel configuration"""
        self.logger.info("Cleaning up tunnel")
        return self.http_client.request('DELETE', f'/id/{self.config.tunnel_id}')

    def run(self) -> None:
        """Main execution loop"""
        with self._tunnel_lifecycle() as success:
            if not success:
                return

            self.logger.info("Tunnel created successfully")
            health_thread = threading.Thread(target=self._monitor_health)
            health_thread.daemon = True
            health_thread.start()

            while self.is_running:
                time.sleep(1)

def main() -> None:
    """CLI entry point"""
    parser = argparse.ArgumentParser(
        description='AetherLink - Secure and reliable tunnel manager',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('host', help='Host domain')
    parser.add_argument('port', help='Port number')
    parser.add_argument('--local-port', help='Local port to tunnel (defaults to port)')
    parser.add_argument('--log-level', default='INFO',
                       choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                       help='Set the logging level')

    args = parser.parse_args()
    config = TunnelConfig(
        host=args.host,
        port=args.port,
        local_port=args.local_port or args.port
    )
    
    AetherLink(config).run()

if __name__ == '__main__':
    main()