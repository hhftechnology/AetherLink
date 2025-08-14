#!/usr/bin/env python3

import argparse
import json
import logging
import os
import signal
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional
from urllib import error, request

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.expanduser('~/.aetherlink/logs/aetherlink.log'))
    ]
)
logger = logging.getLogger('aetherlink')

@dataclass
class TunnelConfig:
    host: str
    port: int
    local_port: Optional[int] = None
    admin_api_url: str = 'http://127.0.0.1:2019'
    retry_attempts: int = 3
    retry_delay: int = 5
    health_check_interval: int = 30

class AetherLinkTunnel:
    def __init__(self, config: TunnelConfig):
        self.config = config
        self.tunnel_id = f"{config.host}-{config.port}"
        self.running = False
        self.last_health_check = 0
        signal.signal(signal.SIGINT, self.handle_shutdown)
        signal.signal(signal.SIGTERM, self.handle_shutdown)

    def create_route_config(self) -> Dict:
        """Generate the Caddy route configuration."""
        return {
            "@id": self.tunnel_id,
            "match": [{
                "host": [self.config.host],
            }],
            "handle": [{
                "handler": "reverse_proxy",
                "upstreams": [{
                    "dial": f":{self.config.port}"
                }],
                "health_checks": {
                    "active": {
                        "interval": f"{self.config.health_check_interval}s",
                        "timeout": "5s"
                    }
                }
            }]
        }

    def make_request(self, method: str, url: str, data: Optional[Dict] = None) -> bool:
        """Make HTTP request with retry mechanism."""
        for attempt in range(self.config.retry_attempts):
            try:
                headers = {'Content-Type': 'application/json'} if data else {}
                req = request.Request(
                    method=method,
                    url=url,
                    headers=headers,
                    data=json.dumps(data).encode('utf-8') if data else None
                )
                with request.urlopen(req, timeout=10) as response:
                    return response.status == 200
            except (error.URLError, error.HTTPError) as e:
                logger.error(f"Request failed (attempt {attempt + 1}/{self.config.retry_attempts}): {e}")
                if attempt < self.config.retry_attempts - 1:
                    time.sleep(self.config.retry_delay)
                else:
                    raise RuntimeError(f"Failed to {method} tunnel after {self.config.retry_attempts} attempts")
        return False

    def create_tunnel(self) -> None:
        """Create a new tunnel configuration in Caddy."""
        logger.info(f"Creating tunnel for {self.config.host} on port {self.config.port}")
        route_config = self.create_route_config()
        create_url = f"{self.config.admin_api_url}/config/apps/http/servers/aetherlink/routes"
        if self.make_request('POST', create_url, route_config):
            logger.info("Tunnel created successfully")
            self.running = True
        else:
            raise RuntimeError("Failed to create tunnel")

    def delete_tunnel(self) -> None:
        """Remove tunnel configuration from Caddy."""
        logger.info(f"Removing tunnel {self.tunnel_id}")
        delete_url = f"{self.config.admin_api_url}/id/{self.tunnel_id}"
        if self.make_request('DELETE', delete_url):
            logger.info("Tunnel removed successfully")
            self.running = False
        else:
            logger.error("Failed to remove tunnel")

    def check_health(self) -> bool:
        """Perform health check on the tunnel."""
        current_time = time.time()
        if current_time - self.last_health_check >= self.config.health_check_interval:
            try:
                health_url = f"http://localhost:{self.config.port}/health"
                with request.urlopen(health_url, timeout=5) as response:
                    healthy = response.status == 200
                    if not healthy:
                        logger.warning(f"Health check failed for {self.tunnel_id}")
                    self.last_health_check = current_time
                    return healthy
            except (error.URLError, error.HTTPError):
                logger.warning(f"Health check failed for {self.tunnel_id}")
                return False
        return True

    def handle_shutdown(self, signum, frame) -> None:
        """Handle graceful shutdown on signals."""
        logger.info("Received shutdown signal")
        self.cleanup()
        sys.exit(0)

    def cleanup(self) -> None:
        """Cleanup resources before shutdown."""
        if self.running:
            try:
                self.delete_tunnel()
            except Exception as e:
                logger.error(f"Error during cleanup: {e}")

    def run(self) -> None:
        """Main tunnel operation loop."""
        try:
            self.create_tunnel()
            logger.info(f"Tunnel established: https://{self.config.host}")
            
            while self.running:
                if not self.check_health():
                    logger.warning("Health check failed, attempting to recreate tunnel")
                    self.cleanup()
                    self.create_tunnel()
                time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
        except Exception as e:
            logger.error(f"Error in tunnel operation: {e}")
        finally:
            self.cleanup()

def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='AetherLink - Secure HTTPS Tunnels')
    parser.add_argument('host', help='Target hostname')
    parser.add_argument('port', type=int, help='Target port')
    parser.add_argument('--local-port', type=int, help='Local port to forward')
    parser.add_argument('--log-level', default='INFO', 
                       choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                       help='Set logging level')
    return parser.parse_args()

def main() -> None:
    """Main entry point."""
    args = parse_arguments()
    logger.setLevel(args.log_level)
    
    # Ensure config directory exists
    config_dir = Path.home() / '.aetherlink' / 'logs'
    config_dir.mkdir(parents=True, exist_ok=True)
    
    config = TunnelConfig(
        host=args.host,
        port=args.port,
        local_port=args.local_port
    )
    
    tunnel = AetherLinkTunnel(config)
    tunnel.run()

if __name__ == '__main__':
    main()