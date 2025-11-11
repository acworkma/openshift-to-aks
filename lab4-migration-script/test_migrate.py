#!/usr/bin/env python3
"""
Basic tests for the OpenShift to AKS migration script
"""

import sys
import os
from unittest.mock import MagicMock

# Mock the kubernetes module to allow testing without installation
sys.modules['kubernetes'] = MagicMock()
sys.modules['kubernetes.client'] = MagicMock()
sys.modules['kubernetes.client.rest'] = MagicMock()
sys.modules['kubernetes.config'] = MagicMock()

# Add the parent directory to the path to import migrate
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from migrate import OpenShiftToAKSMigrator


def test_route_to_ingress_conversion():
    """Test converting OpenShift Route to Kubernetes Ingress"""
    print("Testing Route to Ingress conversion...")
    
    # Sample OpenShift Route
    route = {
        'apiVersion': 'route.openshift.io/v1',
        'kind': 'Route',
        'metadata': {
            'name': 'sample-app',
            'namespace': 'sample-app',
            'labels': {
                'app': 'sample-app'
            }
        },
        'spec': {
            'host': 'sample-app.apps.example.com',
            'to': {
                'kind': 'Service',
                'name': 'sample-app'
            },
            'port': {
                'targetPort': 'http'
            }
        }
    }
    
    migrator = OpenShiftToAKSMigrator()
    ingress = migrator.route_to_ingress(route)
    
    # Validate the conversion
    assert ingress['kind'] == 'Ingress', "Kind should be Ingress"
    assert ingress['apiVersion'] == 'networking.k8s.io/v1', "API version should be networking.k8s.io/v1"
    assert ingress['metadata']['name'] == 'sample-app', "Name should be preserved"
    assert ingress['metadata']['namespace'] == 'sample-app', "Namespace should be preserved"
    assert len(ingress['spec']['rules']) == 1, "Should have one rule"
    assert ingress['spec']['rules'][0]['host'] == 'sample-app.apps.example.com', "Host should be preserved"
    
    print("✓ Route to Ingress conversion test passed")


def test_resource_transformation():
    """Test generic resource transformation"""
    print("Testing resource transformation...")
    
    # Sample resource with metadata to be removed
    resource = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {
            'name': 'test-deployment',
            'namespace': 'test',
            'uid': 'should-be-removed',
            'selfLink': 'should-be-removed',
            'resourceVersion': 'should-be-removed',
            'generation': 123,
            'creationTimestamp': '2024-01-01T00:00:00Z',
            'annotations': {
                'openshift.io/generated-by': 'should-be-removed',
                'kubectl.kubernetes.io/last-applied-configuration': 'should-be-kept'
            }
        },
        'status': {
            'replicas': 3
        }
    }
    
    migrator = OpenShiftToAKSMigrator()
    transformed = migrator.transform_resource(resource)
    
    # Validate transformation
    assert 'uid' not in transformed['metadata'], "UID should be removed"
    assert 'selfLink' not in transformed['metadata'], "selfLink should be removed"
    assert 'resourceVersion' not in transformed['metadata'], "resourceVersion should be removed"
    assert 'generation' not in transformed['metadata'], "generation should be removed"
    assert 'creationTimestamp' not in transformed['metadata'], "creationTimestamp should be removed"
    assert 'status' not in transformed, "Status should be removed"
    assert 'openshift.io/generated-by' not in transformed['metadata']['annotations'], "OpenShift annotations should be removed"
    assert 'kubectl.kubernetes.io/last-applied-configuration' in transformed['metadata']['annotations'], "Non-OpenShift annotations should be kept"
    
    print("✓ Resource transformation test passed")


def test_route_to_ingress_with_tls():
    """Test converting OpenShift Route with TLS to Kubernetes Ingress"""
    print("Testing Route with TLS to Ingress conversion...")
    
    route = {
        'apiVersion': 'route.openshift.io/v1',
        'kind': 'Route',
        'metadata': {
            'name': 'secure-app',
            'namespace': 'test'
        },
        'spec': {
            'host': 'secure-app.example.com',
            'to': {
                'kind': 'Service',
                'name': 'secure-app'
            },
            'port': {
                'targetPort': 'https'
            },
            'tls': {
                'termination': 'edge'
            }
        }
    }
    
    migrator = OpenShiftToAKSMigrator()
    ingress = migrator.route_to_ingress(route)
    
    # Validate TLS configuration
    assert 'tls' in ingress['spec'], "TLS should be present in Ingress"
    assert len(ingress['spec']['tls']) == 1, "Should have one TLS configuration"
    assert ingress['spec']['tls'][0]['hosts'][0] == 'secure-app.example.com', "TLS host should match route host"
    assert ingress['spec']['tls'][0]['secretName'] == 'secure-app-tls', "TLS secret name should be generated"
    
    print("✓ Route with TLS to Ingress conversion test passed")


def main():
    """Run all tests"""
    print("Running OpenShift to AKS migration script tests...\n")
    
    try:
        test_route_to_ingress_conversion()
        test_resource_transformation()
        test_route_to_ingress_with_tls()
        
        print("\n✓ All tests passed!")
        return 0
    except AssertionError as e:
        print(f"\n✗ Test failed: {e}")
        return 1
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
