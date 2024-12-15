"""
Tests for the AetherLink module.
"""
import socket
from unittest.mock import MagicMock, patch

import pytest

from aetherlink import AetherLink


@pytest.fixture
def aetherlink_instance():
    """Create a test instance of AetherLink"""
    with patch('os.makedirs'):  # Mock directory creation
        return AetherLink('test.domain.com', '443', '8080')


def test_initialization(aetherlink_instance):
    """Test AetherLink initialization"""
    assert aetherlink_instance.config['host'] == 'test.domain.com'
    assert aetherlink_instance.config['port'] == '443'
    assert aetherlink_instance.config['local_port'] == '8080'
    assert aetherlink_instance.tunnel_id == 'aetherlink-test.domain.com-443'


def test_create_route_config(aetherlink_instance):
    """Test route configuration creation"""
    config = aetherlink_instance.create_route_config()
    assert config['@id'] == aetherlink_instance.tunnel_id
    assert config['match'][0]['host'] == ['test.domain.com']
    assert config['handle'][0]['upstreams'][0]['dial'] == '127.0.0.1:8080'


@patch('socket.create_connection')
def test_wait_for_service_success(mock_connection, aetherlink_instance):
    """Test service availability check - success case"""
    mock_connection.return_value = MagicMock()
    result = aetherlink_instance.wait_for_service('127.0.0.1', 8080, timeout=1)
    assert result is True
    mock_connection.assert_called_once()


@patch('socket.create_connection')
def test_wait_for_service_failure(mock_connection, aetherlink_instance):
    """Test service availability check - failure case"""
    mock_connection.side_effect = socket.error()
    result = aetherlink_instance.wait_for_service('127.0.0.1', 8080, timeout=1)
    assert result is False


@patch('urllib.request.urlopen')
def test_make_request_success(mock_urlopen, aetherlink_instance):
    """Test HTTP request - success case"""
    mock_response = MagicMock()
    mock_response.status = 200
    mock_urlopen.return_value.__enter__.return_value = mock_response
    
    result = aetherlink_instance.make_request('GET', '/test')
    assert result is True


@patch('urllib.request.urlopen')
def test_make_request_failure(mock_urlopen, aetherlink_instance):
    """Test HTTP request - failure case"""
    mock_urlopen.side_effect = Exception('Test error')
    result = aetherlink_instance.make_request('GET', '/test')
    assert result is False


def test_handle_shutdown(aetherlink_instance):
    """Test shutdown handler"""
    assert aetherlink_instance.is_running is True
    aetherlink_instance.handle_shutdown()
    assert aetherlink_instance.is_running is False