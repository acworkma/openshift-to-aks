#!/usr/bin/env python3
"""
OpenShift to AKS Migration Script

This script documents OpenShift applications and migrates them to Azure Kubernetes Service (AKS).
It handles the transformation of OpenShift-specific resources to standard Kubernetes resources.
"""

import argparse
import json
import logging
import os
import sys
import yaml
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
except ImportError:
    print("Error: kubernetes package not found. Please run: pip install -r requirements.txt")
    sys.exit(1)


class OpenShiftToAKSMigrator:
    """Main class for migrating applications from OpenShift to AKS"""
    
    def __init__(self, source_context: Optional[str] = None, target_context: Optional[str] = None):
        """
        Initialize the migrator
        
        Args:
            source_context: Kubernetes context for OpenShift cluster
            target_context: Kubernetes context for AKS cluster
        """
        self.source_context = source_context
        self.target_context = target_context
        self.logger = logging.getLogger(__name__)
        
    def document_application(self, namespace: str, output_dir: str) -> Dict[str, Any]:
        """
        Document all resources for an application in OpenShift
        
        Args:
            namespace: OpenShift namespace/project
            output_dir: Directory to save exported resources
            
        Returns:
            Dictionary containing export metadata
        """
        self.logger.info(f"Documenting application in namespace: {namespace}")
        
        # Load source cluster configuration
        if self.source_context:
            config.load_kube_config(context=self.source_context)
        else:
            config.load_kube_config()
        
        # Create output directory
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Initialize API clients
        apps_v1 = client.AppsV1Api()
        core_v1 = client.CoreV1Api()
        
        export_data = {
            'namespace': namespace,
            'timestamp': datetime.utcnow().isoformat(),
            'resources': {}
        }
        
        # Export Deployments
        try:
            deployments = apps_v1.list_namespaced_deployment(namespace)
            deployment_list = []
            for deployment in deployments.items:
                deployment_dict = client.ApiClient().sanitize_for_serialization(deployment)
                deployment_list.append(deployment_dict)
            
            if deployment_list:
                with open(output_path / 'deployments.yaml', 'w') as f:
                    yaml.dump_all(deployment_list, f, default_flow_style=False)
                export_data['resources']['deployments'] = len(deployment_list)
                self.logger.info(f"Exported {len(deployment_list)} deployment(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export deployments: {e}")
        
        # Export Services
        try:
            services = core_v1.list_namespaced_service(namespace)
            service_list = []
            for service in services.items:
                # Skip default kubernetes service
                if service.metadata.name == 'kubernetes':
                    continue
                service_dict = client.ApiClient().sanitize_for_serialization(service)
                service_list.append(service_dict)
            
            if service_list:
                with open(output_path / 'services.yaml', 'w') as f:
                    yaml.dump_all(service_list, f, default_flow_style=False)
                export_data['resources']['services'] = len(service_list)
                self.logger.info(f"Exported {len(service_list)} service(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export services: {e}")
        
        # Export ConfigMaps
        try:
            configmaps = core_v1.list_namespaced_config_map(namespace)
            configmap_list = []
            for cm in configmaps.items:
                # Skip system ConfigMaps
                if cm.metadata.name.startswith('kube-') or cm.metadata.name.startswith('openshift-'):
                    continue
                cm_dict = client.ApiClient().sanitize_for_serialization(cm)
                configmap_list.append(cm_dict)
            
            if configmap_list:
                with open(output_path / 'configmaps.yaml', 'w') as f:
                    yaml.dump_all(configmap_list, f, default_flow_style=False)
                export_data['resources']['configmaps'] = len(configmap_list)
                self.logger.info(f"Exported {len(configmap_list)} configmap(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export configmaps: {e}")
        
        # Export Secrets
        try:
            secrets = core_v1.list_namespaced_secret(namespace)
            secret_list = []
            for secret in secrets.items:
                # Skip service account tokens and system secrets
                if (secret.type == 'kubernetes.io/service-account-token' or 
                    secret.metadata.name.startswith('default-token-') or
                    secret.metadata.name.startswith('builder-token-')):
                    continue
                secret_dict = client.ApiClient().sanitize_for_serialization(secret)
                secret_list.append(secret_dict)
            
            if secret_list:
                with open(output_path / 'secrets.yaml', 'w') as f:
                    yaml.dump_all(secret_list, f, default_flow_style=False)
                export_data['resources']['secrets'] = len(secret_list)
                self.logger.info(f"Exported {len(secret_list)} secret(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export secrets: {e}")
        
        # Try to export Routes (OpenShift-specific)
        try:
            custom_api = client.CustomObjectsApi()
            routes = custom_api.list_namespaced_custom_object(
                group="route.openshift.io",
                version="v1",
                namespace=namespace,
                plural="routes"
            )
            
            if routes.get('items'):
                with open(output_path / 'routes.yaml', 'w') as f:
                    yaml.dump_all(routes['items'], f, default_flow_style=False)
                export_data['resources']['routes'] = len(routes['items'])
                self.logger.info(f"Exported {len(routes['items'])} route(s)")
        except Exception as e:
            self.logger.info(f"No routes found or not an OpenShift cluster: {e}")
        
        # Save export metadata
        with open(output_path / 'migration-report.json', 'w') as f:
            json.dump(export_data, f, indent=2)
        
        self.logger.info(f"Export complete. Files saved to: {output_dir}")
        return export_data
    
    def transform_resource(self, resource: Dict[str, Any]) -> Dict[str, Any]:
        """
        Transform OpenShift resource to AKS-compatible format
        
        Args:
            resource: Resource dictionary
            
        Returns:
            Transformed resource dictionary
        """
        # Remove OpenShift-specific metadata
        if 'metadata' in resource:
            metadata = resource['metadata']
            # Remove fields that shouldn't be migrated
            for field in ['uid', 'selfLink', 'resourceVersion', 'generation', 'creationTimestamp']:
                metadata.pop(field, None)
            
            # Clean annotations
            if 'annotations' in metadata:
                annotations = metadata['annotations']
                # Remove OpenShift-specific annotations
                openshift_annotations = [key for key in annotations if key.startswith('openshift.io/')]
                for key in openshift_annotations:
                    del annotations[key]
        
        # Remove status field
        resource.pop('status', None)
        
        return resource
    
    def route_to_ingress(self, route: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert OpenShift Route to Kubernetes Ingress
        
        Args:
            route: OpenShift Route resource
            
        Returns:
            Kubernetes Ingress resource
        """
        spec = route.get('spec', {})
        metadata = route.get('metadata', {})
        
        # Create Ingress resource
        ingress = {
            'apiVersion': 'networking.k8s.io/v1',
            'kind': 'Ingress',
            'metadata': {
                'name': metadata.get('name'),
                'namespace': metadata.get('namespace'),
                'labels': metadata.get('labels', {}),
                'annotations': {
                    'kubernetes.io/ingress.class': 'nginx'
                }
            },
            'spec': {
                'rules': []
            }
        }
        
        # Extract host from route
        host = spec.get('host', '')
        service_name = spec.get('to', {}).get('name', '')
        target_port = spec.get('port', {}).get('targetPort', 'http')
        
        if host and service_name:
            rule = {
                'host': host,
                'http': {
                    'paths': [
                        {
                            'path': spec.get('path', '/'),
                            'pathType': 'Prefix',
                            'backend': {
                                'service': {
                                    'name': service_name,
                                    'port': {
                                        'name': target_port if isinstance(target_port, str) else 'http'
                                    }
                                }
                            }
                        }
                    ]
                }
            }
            ingress['spec']['rules'].append(rule)
        
        # Add TLS if route has TLS
        if spec.get('tls'):
            ingress['spec']['tls'] = [
                {
                    'hosts': [host],
                    'secretName': f"{metadata.get('name')}-tls"
                }
            ]
        
        return ingress
    
    def migrate_application(self, namespace: str, output_dir: str, apply: bool = False) -> bool:
        """
        Migrate application from OpenShift to AKS
        
        Args:
            namespace: Source namespace
            output_dir: Directory to save transformed resources
            apply: Whether to apply resources to target cluster
            
        Returns:
            True if successful, False otherwise
        """
        # First, document the application
        export_data = self.document_application(namespace, f"{output_dir}/source")
        
        # Create output directory for AKS manifests
        aks_output = Path(output_dir) / 'aks'
        aks_output.mkdir(parents=True, exist_ok=True)
        
        source_dir = Path(output_dir) / 'source'
        
        # Transform deployments
        if (source_dir / 'deployments.yaml').exists():
            with open(source_dir / 'deployments.yaml', 'r') as f:
                deployments = list(yaml.safe_load_all(f))
            
            transformed_deployments = [self.transform_resource(d) for d in deployments if d]
            
            with open(aks_output / 'deployments.yaml', 'w') as f:
                yaml.dump_all(transformed_deployments, f, default_flow_style=False)
        
        # Transform services
        if (source_dir / 'services.yaml').exists():
            with open(source_dir / 'services.yaml', 'r') as f:
                services = list(yaml.safe_load_all(f))
            
            transformed_services = [self.transform_resource(s) for s in services if s]
            
            with open(aks_output / 'services.yaml', 'w') as f:
                yaml.dump_all(transformed_services, f, default_flow_style=False)
        
        # Transform ConfigMaps
        if (source_dir / 'configmaps.yaml').exists():
            with open(source_dir / 'configmaps.yaml', 'r') as f:
                configmaps = list(yaml.safe_load_all(f))
            
            transformed_configmaps = [self.transform_resource(cm) for cm in configmaps if cm]
            
            with open(aks_output / 'configmaps.yaml', 'w') as f:
                yaml.dump_all(transformed_configmaps, f, default_flow_style=False)
        
        # Transform Routes to Ingress
        if (source_dir / 'routes.yaml').exists():
            with open(source_dir / 'routes.yaml', 'r') as f:
                routes = list(yaml.safe_load_all(f))
            
            ingresses = [self.route_to_ingress(route) for route in routes if route]
            
            if ingresses:
                with open(aks_output / 'ingresses.yaml', 'w') as f:
                    yaml.dump_all(ingresses, f, default_flow_style=False)
        
        # Copy secrets (with warning about reviewing them)
        if (source_dir / 'secrets.yaml').exists():
            with open(source_dir / 'secrets.yaml', 'r') as f:
                secrets = list(yaml.safe_load_all(f))
            
            transformed_secrets = [self.transform_resource(s) for s in secrets if s]
            
            with open(aks_output / 'secrets.yaml', 'w') as f:
                yaml.dump_all(transformed_secrets, f, default_flow_style=False)
            
            self.logger.warning("Secrets have been exported. Please review them before applying to AKS.")
        
        self.logger.info(f"Transformation complete. AKS manifests saved to: {aks_output}")
        
        # Apply to AKS if requested
        if apply:
            return self.apply_to_aks(namespace, aks_output)
        
        return True
    
    def apply_to_aks(self, namespace: str, manifest_dir: Path) -> bool:
        """
        Apply transformed manifests to AKS cluster
        
        Args:
            namespace: Target namespace in AKS
            manifest_dir: Directory containing AKS manifests
            
        Returns:
            True if successful, False otherwise
        """
        self.logger.info(f"Applying resources to AKS cluster in namespace: {namespace}")
        
        # Load target cluster configuration
        if self.target_context:
            config.load_kube_config(context=self.target_context)
        else:
            config.load_kube_config()
        
        # Initialize API clients
        core_v1 = client.CoreV1Api()
        apps_v1 = client.AppsV1Api()
        networking_v1 = client.NetworkingV1Api()
        
        # Create namespace if it doesn't exist
        try:
            core_v1.read_namespace(namespace)
            self.logger.info(f"Namespace {namespace} already exists")
        except ApiException as e:
            if e.status == 404:
                self.logger.info(f"Creating namespace: {namespace}")
                namespace_obj = client.V1Namespace(metadata=client.V1ObjectMeta(name=namespace))
                core_v1.create_namespace(namespace_obj)
            else:
                raise
        
        # Apply ConfigMaps
        if (manifest_dir / 'configmaps.yaml').exists():
            with open(manifest_dir / 'configmaps.yaml', 'r') as f:
                configmaps = list(yaml.safe_load_all(f))
            
            for cm in configmaps:
                if cm:
                    try:
                        core_v1.create_namespaced_config_map(namespace, cm)
                        self.logger.info(f"Created ConfigMap: {cm['metadata']['name']}")
                    except ApiException as e:
                        if e.status == 409:
                            self.logger.warning(f"ConfigMap {cm['metadata']['name']} already exists")
                        else:
                            self.logger.error(f"Error creating ConfigMap: {e}")
        
        # Apply Secrets
        if (manifest_dir / 'secrets.yaml').exists():
            with open(manifest_dir / 'secrets.yaml', 'r') as f:
                secrets = list(yaml.safe_load_all(f))
            
            for secret in secrets:
                if secret:
                    try:
                        core_v1.create_namespaced_secret(namespace, secret)
                        self.logger.info(f"Created Secret: {secret['metadata']['name']}")
                    except ApiException as e:
                        if e.status == 409:
                            self.logger.warning(f"Secret {secret['metadata']['name']} already exists")
                        else:
                            self.logger.error(f"Error creating Secret: {e}")
        
        # Apply Deployments
        if (manifest_dir / 'deployments.yaml').exists():
            with open(manifest_dir / 'deployments.yaml', 'r') as f:
                deployments = list(yaml.safe_load_all(f))
            
            for deployment in deployments:
                if deployment:
                    try:
                        apps_v1.create_namespaced_deployment(namespace, deployment)
                        self.logger.info(f"Created Deployment: {deployment['metadata']['name']}")
                    except ApiException as e:
                        if e.status == 409:
                            self.logger.warning(f"Deployment {deployment['metadata']['name']} already exists")
                        else:
                            self.logger.error(f"Error creating Deployment: {e}")
        
        # Apply Services
        if (manifest_dir / 'services.yaml').exists():
            with open(manifest_dir / 'services.yaml', 'r') as f:
                services = list(yaml.safe_load_all(f))
            
            for service in services:
                if service:
                    try:
                        core_v1.create_namespaced_service(namespace, service)
                        self.logger.info(f"Created Service: {service['metadata']['name']}")
                    except ApiException as e:
                        if e.status == 409:
                            self.logger.warning(f"Service {service['metadata']['name']} already exists")
                        else:
                            self.logger.error(f"Error creating Service: {e}")
        
        # Apply Ingresses
        if (manifest_dir / 'ingresses.yaml').exists():
            with open(manifest_dir / 'ingresses.yaml', 'r') as f:
                ingresses = list(yaml.safe_load_all(f))
            
            for ingress in ingresses:
                if ingress:
                    try:
                        networking_v1.create_namespaced_ingress(namespace, ingress)
                        self.logger.info(f"Created Ingress: {ingress['metadata']['name']}")
                    except ApiException as e:
                        if e.status == 409:
                            self.logger.warning(f"Ingress {ingress['metadata']['name']} already exists")
                        else:
                            self.logger.error(f"Error creating Ingress: {e}")
        
        self.logger.info("Application successfully deployed to AKS")
        return True


def main():
    """Main entry point for the migration script"""
    parser = argparse.ArgumentParser(
        description='Migrate applications from OpenShift to Azure Kubernetes Service (AKS)',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Document command
    doc_parser = subparsers.add_parser('document', help='Document OpenShift application')
    doc_parser.add_argument('--namespace', required=True, help='OpenShift namespace/project')
    doc_parser.add_argument('--output', required=True, help='Output directory for exported resources')
    doc_parser.add_argument('--context', help='Kubernetes context for OpenShift cluster')
    
    # Migrate command
    migrate_parser = subparsers.add_parser('migrate', help='Migrate application from OpenShift to AKS')
    migrate_parser.add_argument('--namespace', required=True, help='Source namespace')
    migrate_parser.add_argument('--source-context', help='Kubernetes context for OpenShift cluster')
    migrate_parser.add_argument('--target-context', help='Kubernetes context for AKS cluster')
    migrate_parser.add_argument('--output', required=True, help='Output directory for migrated resources')
    migrate_parser.add_argument('--apply', action='store_true', help='Apply resources to AKS')
    
    # Global options
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Configure logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Execute command
    if args.command == 'document':
        migrator = OpenShiftToAKSMigrator(source_context=args.context)
        migrator.document_application(args.namespace, args.output)
    
    elif args.command == 'migrate':
        migrator = OpenShiftToAKSMigrator(
            source_context=args.source_context,
            target_context=args.target_context
        )
        success = migrator.migrate_application(args.namespace, args.output, args.apply)
        if not success:
            sys.exit(1)
    
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
