"""
AetherLink - Secure and reliable tunnel manager for creating and managing 
secure tunnels between local and remote services. This module provides the core
functionality for tunnel creation, management, and monitoring.
"""

import argparse
import json
import logging
import os
import signal
import socket
import threading
import time
from typing import Optional
from urllib import request


class AetherLink:
    """
    AetherLink - Secure and reliable tunnel manager
    Creates and manages secure tunnels between local and remote services
    """

    def __init__(self, host: str, port: str, local_port: str = None):
        """Initialize AetherLink with host and port configuration."""
        self.config = {
            'host': host,
            'port': port,
            'local_port': local_port or port,
            'base_url': "http://127.0.0.1:2019",
            'health_check_interval': 5
        }
        self.tunnel_id = f"aetherlink-{host}-{port}"
        self.is_running = True
        self.logger = None  # Will be set in setup_logging

        self._setup_environment()
        self.setup_logging()
        self.setup_signal_handlers()

    def _setup_environment(self):
        """Setup necessary directories and files"""
        os.makedirs('logs', exist_ok=True)
        os.makedirs('config', exist_ok=True)

    def setup_logging(self):
        """Configure logging with both file and console output"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(),
                logging.FileHandler(os.path.join('logs', 'aetherlink.log'))
            ]
        )
        self.logger = logging.getLogger('AetherLink')

    def setup_signal_handlers(self):
        """Setup handlers for graceful shutdown"""
        signal.signal(signal.SIGINT, self.handle_shutdown)
        signal.signal(signal.SIGTERM, self.handle_shutdown)

    def create_route_config(self) -> dict:
        """Create the routing configuration for the tunnel"""
        return {
            "@id": self.tunnel_id,
            "match": [{
                "host": [self.config['host']],
            }],
            "handle": [{
                "handler": "reverse_proxy",
                "upstreams": [{
                    "dial": f"127.0.0.1:{self.config['local_port']}"
                }],
                "health_checks": {
                    "active": {
                        "interval": "10s",
                        "timeout": "5s",
                        "uri": "/",
                        "host": self.config['host']
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

    def wait_for_service(
        self, host: str, port: int, timeout: int = 30, service_name: str = "Service"
    ) -> bool:
        """Generic service availability checker"""
        self.logger.info("Waiting for %s on %s:%s", service_name, host, port)
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                socket.create_connection((host, port), timeout=2)
                self.logger.info("%s is available", service_name)
                return True
            except (socket.timeout, socket.error) as e:
                if time.time() - start_time >= timeout:
                    self.logger.error("%s is not available: %s", service_name, e)
                    return False
            time.sleep(1)
        return False

    def wait_for_local_service(self) -> bool:
        """Wait for local service to become available"""
        return self.wait_for_service(
            '127.0.0.1',
            int(self.config['local_port']),
            service_name="Local service"
        )

    def wait_for_caddy(self) -> bool:
        """Wait for Caddy admin API to become available"""
        return self.wait_for_service('127.0.0.1', 2019, service_name="Caddy admin API")

    def make_request(
        self, method: str, url: str, data: Optional[dict] = None, retries: int = 3
    ) -> bool:
        """Make HTTP request with retries"""
        for attempt in range(retries):
            try:
                headers = {'Content-Type': 'application/json'} if data else {}
                req = request.Request(
                    method=method,
                    url=f"{self.config['base_url']}{url}",
                    headers=headers,
                    data=json.dumps(data).encode('utf-8') if data else None
                )
                with request.urlopen(req, timeout=10) as response:
                    return response.status == 200
            except (request.URLError, request.HTTPError) as e:
                if attempt == retries - 1:
                    self.logger.error(
                        "Request failed after %d attempts: %s", retries, e
                    )
                    return False
                time.sleep(1)
        return False

    def handle_shutdown(self, *_args):
        """Handle shutdown signals gracefully"""
        self.logger.info("Received shutdown signal")
        self.is_running = False

    def monitor_health(self):
        """Monitor the health of local service and tunnel"""
        while self.is_running:
            if not self.wait_for_service(
                '127.0.0.1',
                int(self.config['local_port']),
                timeout=2,
                service_name="Local service"
            ):
                self.logger.error("Local service is not responding")
            time.sleep(self.config['health_check_interval'])

    def create_tunnel(self) -> bool:
        """Create the tunnel with all necessary checks"""
        if not self.wait_for_local_service():
            return False

        if not self.wait_for_caddy():
            return False

        self.logger.info(
            "Creating tunnel for %s:%s",
            self.config['host'],
            self.config['port']
        )
        config = self.create_route_config()
        return self.make_request(
            'POST', '/config/apps/http/servers/aetherlink/routes', config
        )

    def delete_tunnel(self) -> bool:
        """Clean up the tunnel"""
        self.logger.info("Cleaning up tunnel")
        return self.make_request('DELETE', f'/id/{self.tunnel_id}')

    def run(self):
        """Main execution loop"""
        if not self.create_tunnel():
            self.logger.error("Failed to create tunnel")
            return

        self.logger.info("Tunnel created successfully")

        health_thread = threading.Thread(target=self.monitor_health)
        health_thread.daemon = True
        health_thread.start()

        try:
            while self.is_running:
                time.sleep(1)
        finally:
            if not self.delete_tunnel():
                self.logger.error("Failed to clean up tunnel")


def main():
    """Entry point for the AetherLink application"""
    parser = argparse.ArgumentParser(
        description='AetherLink - Secure and reliable tunnel manager',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('host', help='Host domain')
    parser.add_argument('port', help='Port number')
    parser.add_argument(
        '--local-port', help='Local port to tunnel (defaults to port)'
    )
    parser.add_argument(
        '--log-level',
        default='INFO',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
        help='Set the logging level'
    )

    args = parser.parse_args()

    aetherlink = AetherLink(args.host, args.port, args.local_port)
    aetherlink.run()


if __name__ == '__main__':
    main()