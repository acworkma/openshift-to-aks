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
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional, Set

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
    KUBERNETES_AVAILABLE = True
except ImportError:
    KUBERNETES_AVAILABLE = False
    # Only show error if not just displaying help
    if not (len(sys.argv) >= 2 and '-h' in sys.argv or '--help' in sys.argv):
        print("Error: kubernetes package not found. Please run: pip install -r requirements.txt", file=sys.stderr)
        if len(sys.argv) > 1:  # Only exit if trying to run a command
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

    def extract_images_from_manifests(self, manifest_dir: Path) -> Set[str]:
        """
        Extract all unique container images from workload manifests in a directory.
        """
        image_set: Set[str] = set()
        workload_files = ['deployments.yaml', 'statefulsets.yaml', 'jobs.yaml', 'cronjobs.yaml', 'deploymentconfigs.yaml']
        for fname in workload_files:
            path = manifest_dir / fname
            if not path.exists():
                continue
            with open(path, 'r') as f:
                docs = list(yaml.safe_load_all(f))
            for doc in docs:
                if not doc:
                    continue
                kind = doc.get('kind')
                containers: List[Dict[str, Any]] = []
                if kind in ['Deployment', 'StatefulSet', 'DeploymentConfig']:
                    containers = doc.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                elif kind == 'Job':
                    containers = doc.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                elif kind == 'CronJob':
                    containers = doc.get('spec', {}).get('jobTemplate', {}).get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                # Fallback if kind missing
                if not containers:
                    fallback = doc.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                    if fallback:
                        containers = fallback
                # Fallback via applied configuration annotation
                if not containers and 'metadata' in doc and 'annotations' in doc['metadata']:
                    applied_cfg = doc['metadata']['annotations'].get('kubectl.kubernetes.io/last-applied-configuration')
                    if applied_cfg:
                        try:
                            applied_json = json.loads(applied_cfg)
                            annotation_containers = applied_json.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                            if annotation_containers:
                                containers = annotation_containers
                        except Exception:
                            pass
                for c in containers:
                    image = c.get('image')
                    if image:
                        image_set.add(image)
        return image_set

    def import_images_to_acr(self, images: Set[str], acr_login_server: str, acr_name: str,
                              ghcr_username: Optional[str], ghcr_token: Optional[str]) -> None:
        """Import images into ACR with authenticated fallback.

        1. Try direct 'az acr import' (include GHCR source creds if provided).
        2. On DENIED/403/UNAUTHORIZED, fallback to docker pull/tag/push.
        Credentials are never logged.
        """
        for image in images:
            if image.startswith(acr_login_server):
                self.logger.info(f"Image already in ACR: {image}")
                continue
            image_name = image.split('/')[-1]
            acr_image = f"{acr_login_server}/{image_name}"
            self.logger.info(f"Importing {image} to {acr_image}")
            cmd = ['az', 'acr', 'import', '--name', acr_name, '--source', image, '--image', image_name, '--force']
            if ghcr_username and ghcr_token:
                cmd.extend(['--username', ghcr_username, '--password', ghcr_token])
            try:
                subprocess.run(cmd, check=True, capture_output=True)
                self.logger.info(f"Imported {image} to {acr_image}")
            except subprocess.CalledProcessError as e:
                stderr = (e.stderr.decode() if e.stderr else '').upper()
                self.logger.warning(f"Direct import failed for {image}; attempting Docker fallback.")
                if any(token in stderr for token in ['DENIED', '403', 'UNAUTHORIZED']):
                    try:
                        if ghcr_username and ghcr_token:
                            self.logger.info("Logging into GHCR for fallback")
                            subprocess.run(['docker','login','ghcr.io','-u',ghcr_username,'--password-stdin'],
                                           input=ghcr_token.encode(), check=True, capture_output=True)
                        self.logger.info(f"Pulling source image {image}")
                        subprocess.run(['docker','pull',image], check=True, capture_output=True)
                        self.logger.info(f"Logging into ACR {acr_name}")
                        subprocess.run(['az','acr','login','--name',acr_name], check=True, capture_output=True)
                        self.logger.info(f"Tagging {image} as {acr_image}")
                        subprocess.run(['docker','tag',image,acr_image], check=True, capture_output=True)
                        self.logger.info(f"Pushing {acr_image}")
                        subprocess.run(['docker','push',acr_image], check=True, capture_output=True)
                        self.logger.info(f"Fallback push complete for {image}")
                    except subprocess.CalledProcessError as fe:
                        self.logger.error(f"Fallback failed for {image}: {(fe.stderr.decode() if fe.stderr else fe)}")
                else:
                    self.logger.error(f"Import failed for {image}: {(e.stderr.decode() if e.stderr else e)}")

    def rewrite_images_for_acr(self, manifest_dir: Path, acr_login_server: str):
        """
        Rewrite all image references in workload manifests to use the ACR login server.
        """
        workload_files = ['deployments.yaml', 'statefulsets.yaml', 'jobs.yaml', 'cronjobs.yaml', 'deploymentconfigs.yaml']
        for fname in workload_files:
            path = manifest_dir / fname
            if not path.exists():
                continue
            with open(path, 'r') as f:
                docs = list(yaml.safe_load_all(f))
            changed = False
            for doc in docs:
                if not doc:
                    continue
                kind = doc.get('kind')
                containers: List[Dict[str, Any]] = []
                if kind in ['Deployment', 'StatefulSet', 'DeploymentConfig']:
                    containers = doc.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                elif kind == 'Job':
                    containers = doc.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                elif kind == 'CronJob':
                    containers = doc.get('spec', {}).get('jobTemplate', {}).get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                if not containers:
                    containers = doc.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                for c in containers:
                    image = c.get('image')
                    if image and not image.startswith(acr_login_server):
                        image_name = image.split('/')[-1]
                        c['image'] = f"{acr_login_server}/{image_name}"
                        changed = True
            if changed:
                with open(path, 'w') as f:
                    yaml.dump_all(docs, f, default_flow_style=False)

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
                # Ensure kind/apiVersion present for downstream processing
                deployment_dict.setdefault('kind', 'Deployment')
                deployment_dict.setdefault('apiVersion', 'apps/v1')
                deployment_list.append(deployment_dict)
            if deployment_list:
                with open(output_path / 'deployments.yaml', 'w') as f:
                    yaml.dump_all(deployment_list, f, default_flow_style=False)
                export_data['resources']['deployments'] = len(deployment_list)
                self.logger.info(f"Exported {len(deployment_list)} deployment(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export deployments: {e}")

        # Export StatefulSets
        try:
            statefulsets = apps_v1.list_namespaced_stateful_set(namespace)
            ss_list = []
            for ss in statefulsets.items:
                ss_dict = client.ApiClient().sanitize_for_serialization(ss)
                ss_dict.setdefault('kind', 'StatefulSet')
                ss_dict.setdefault('apiVersion', 'apps/v1')
                ss_list.append(ss_dict)
            if ss_list:
                with open(output_path / 'statefulsets.yaml', 'w') as f:
                    yaml.dump_all(ss_list, f, default_flow_style=False)
                export_data['resources']['statefulsets'] = len(ss_list)
                self.logger.info(f"Exported {len(ss_list)} statefulset(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export statefulsets: {e}")

        # Export Jobs and CronJobs
        batch_v1 = client.BatchV1Api()
        batch_v1beta1 = getattr(client, 'BatchV1beta1Api', None)
        try:
            jobs = batch_v1.list_namespaced_job(namespace)
            job_list = []
            for job in jobs.items:
                job_dict = client.ApiClient().sanitize_for_serialization(job)
                job_dict.setdefault('kind', 'Job')
                job_dict.setdefault('apiVersion', 'batch/v1')
                job_list.append(job_dict)
            if job_list:
                with open(output_path / 'jobs.yaml', 'w') as f:
                    yaml.dump_all(job_list, f, default_flow_style=False)
                export_data['resources']['jobs'] = len(job_list)
                self.logger.info(f"Exported {len(job_list)} job(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export jobs: {e}")

        # Export CronJobs (try both v1 and v1beta1 for compatibility)
        try:
            cronjobs = batch_v1.list_namespaced_cron_job(namespace)
            cronjob_list = []
            for cj in cronjobs.items:
                cj_dict = client.ApiClient().sanitize_for_serialization(cj)
                cj_dict.setdefault('kind', 'CronJob')
                cj_dict.setdefault('apiVersion', 'batch/v1')
                cronjob_list.append(cj_dict)
            if cronjob_list:
                with open(output_path / 'cronjobs.yaml', 'w') as f:
                    yaml.dump_all(cronjob_list, f, default_flow_style=False)
                export_data['resources']['cronjobs'] = len(cronjob_list)
                self.logger.info(f"Exported {len(cronjob_list)} cronjob(s)")
        except Exception as e:
            self.logger.warning(f"Could not export cronjobs: {e}")

        # Export PVCs
        try:
            pvcs = core_v1.list_namespaced_persistent_volume_claim(namespace)
            pvc_list = []
            for pvc in pvcs.items:
                pvc_dict = client.ApiClient().sanitize_for_serialization(pvc)
                pvc_dict.setdefault('kind', 'PersistentVolumeClaim')
                pvc_dict.setdefault('apiVersion', 'v1')
                pvc_list.append(pvc_dict)
            if pvc_list:
                with open(output_path / 'pvcs.yaml', 'w') as f:
                    yaml.dump_all(pvc_list, f, default_flow_style=False)
                export_data['resources']['pvcs'] = len(pvc_list)
                self.logger.info(f"Exported {len(pvc_list)} pvc(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export pvcs: {e}")

        # Export ServiceAccounts
        try:
            sas = core_v1.list_namespaced_service_account(namespace)
            sa_list = []
            for sa in sas.items:
                sa_dict = client.ApiClient().sanitize_for_serialization(sa)
                sa_dict.setdefault('kind', 'ServiceAccount')
                sa_dict.setdefault('apiVersion', 'v1')
                sa_list.append(sa_dict)
            if sa_list:
                with open(output_path / 'serviceaccounts.yaml', 'w') as f:
                    yaml.dump_all(sa_list, f, default_flow_style=False)
                export_data['resources']['serviceaccounts'] = len(sa_list)
                self.logger.info(f"Exported {len(sa_list)} serviceaccount(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export serviceaccounts: {e}")

        # Export DeploymentConfigs (OpenShift-specific)
        try:
            custom_api = client.CustomObjectsApi()
            dcs = custom_api.list_namespaced_custom_object(
                group="apps.openshift.io",
                version="v1",
                namespace=namespace,
                plural="deploymentconfigs"
            )
            if dcs.get('items'):
                with open(output_path / 'deploymentconfigs.yaml', 'w') as f:
                    yaml.dump_all(dcs['items'], f, default_flow_style=False)
                export_data['resources']['deploymentconfigs'] = len(dcs['items'])
                self.logger.warning(f"Found {len(dcs['items'])} DeploymentConfig(s). These should be converted to standard Deployments for AKS.")
        except Exception as e:
            self.logger.info(f"No deploymentconfigs found or not an OpenShift cluster: {e}")

        # Export Services (original logic)
        try:
            services = core_v1.list_namespaced_service(namespace)
            service_list = []
            for service in services.items:
                if service.metadata.name == 'kubernetes':
                    continue
                service_dict = client.ApiClient().sanitize_for_serialization(service)
                service_dict.setdefault('kind', 'Service')
                service_dict.setdefault('apiVersion', 'v1')
                service_list.append(service_dict)
            if service_list:
                with open(output_path / 'services.yaml', 'w') as f:
                    yaml.dump_all(service_list, f, default_flow_style=False)
                export_data['resources']['services'] = len(service_list)
                self.logger.info(f"Exported {len(service_list)} service(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export services: {e}")

        # Export ConfigMaps (original logic)
        try:
            configmaps = core_v1.list_namespaced_config_map(namespace)
            configmap_list = []
            for cm in configmaps.items:
                if cm.metadata.name.startswith('kube-') or cm.metadata.name.startswith('openshift-'):
                    continue
                cm_dict = client.ApiClient().sanitize_for_serialization(cm)
                cm_dict.setdefault('kind', 'ConfigMap')
                cm_dict.setdefault('apiVersion', 'v1')
                configmap_list.append(cm_dict)
            if configmap_list:
                with open(output_path / 'configmaps.yaml', 'w') as f:
                    yaml.dump_all(configmap_list, f, default_flow_style=False)
                export_data['resources']['configmaps'] = len(configmap_list)
                self.logger.info(f"Exported {len(configmap_list)} configmap(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export configmaps: {e}")

        # Export Secrets (original logic)
        try:
            secrets = core_v1.list_namespaced_secret(namespace)
            secret_list = []
            for secret in secrets.items:
                if (secret.type == 'kubernetes.io/service-account-token' or 
                    secret.metadata.name.startswith('default-token-') or
                    secret.metadata.name.startswith('builder-token-')):
                    continue
                secret_dict = client.ApiClient().sanitize_for_serialization(secret)
                secret_dict.setdefault('kind', 'Secret')
                secret_dict.setdefault('apiVersion', 'v1')
                secret_list.append(secret_dict)
            if secret_list:
                with open(output_path / 'secrets.yaml', 'w') as f:
                    yaml.dump_all(secret_list, f, default_flow_style=False)
                export_data['resources']['secrets'] = len(secret_list)
                self.logger.info(f"Exported {len(secret_list)} secret(s)")
        except ApiException as e:
            self.logger.warning(f"Could not export secrets: {e}")

        # Try to export Routes (OpenShift-specific, original logic)
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

        # Warn on BuildConfigs, ImageStreams, Templates, SCCs, CRDs
        try:
            custom_api = client.CustomObjectsApi()
            # BuildConfigs
            bcs = custom_api.list_namespaced_custom_object(
                group="build.openshift.io",
                version="v1",
                namespace=namespace,
                plural="buildconfigs"
            )
            if bcs.get('items'):
                self.logger.warning(f"Found {len(bcs['items'])} BuildConfig(s). These are OpenShift-specific and should be replaced with external CI/CD.")
            # ImageStreams
            iss = custom_api.list_namespaced_custom_object(
                group="image.openshift.io",
                version="v1",
                namespace=namespace,
                plural="imagestreams"
            )
            if iss.get('items'):
                self.logger.warning(f"Found {len(iss['items'])} ImageStream(s). These are OpenShift-specific and should be replaced with direct image references.")
            # Templates
            templates = custom_api.list_namespaced_custom_object(
                group="template.openshift.io",
                version="v1",
                namespace=namespace,
                plural="templates"
            )
            if templates.get('items'):
                self.logger.warning(f"Found {len(templates['items'])} Template(s). These are OpenShift-specific and should be converted to Helm/Kustomize.")
            # SCCs (cluster-scoped, not namespaced)
            try:
                sccs = custom_api.list_cluster_custom_object(
                    group="security.openshift.io",
                    version="v1",
                    plural="securitycontextconstraints"
                )
                if sccs.get('items'):
                    self.logger.warning(f"Cluster has {len(sccs['items'])} SCC(s). These are OpenShift-specific and should be reviewed for AKS RBAC/PodSecurity.")
            except Exception:
                pass
            # CRDs
            try:
                crds = custom_api.list_cluster_custom_object(
                    group="apiextensions.k8s.io",
                    version="v1",
                    plural="customresourcedefinitions"
                )
                if crds.get('items'):
                    self.logger.warning(f"Cluster has {len(crds['items'])} CRD(s). Custom resources may require manual migration.")
            except Exception:
                pass
        except Exception as e:
            self.logger.info(f"Could not check for OpenShift-specific resources: {e}")

        # Save export metadata
        with open(output_path / 'migration-report.json', 'w') as f:
            json.dump(export_data, f, indent=2)

        self.logger.info(f"Export complete. Files saved to: {output_dir}")
        return export_data
    
    def transform_resource(self, resource: Dict[str, Any], registry_rewrite: Optional[str] = None,
                           target_namespace: Optional[str] = None) -> Dict[str, Any]:
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
            for field in ['uid', 'selfLink', 'resourceVersion', 'generation', 'creationTimestamp']:
                metadata.pop(field, None)
            if 'annotations' in metadata:
                annotations = metadata['annotations']
                openshift_annotations = [key for key in annotations if key.startswith('openshift.io/')]
                for key in openshift_annotations:
                    del annotations[key]

        # Namespace remap
        if target_namespace and 'metadata' in resource and 'namespace' in resource['metadata']:
            resource['metadata']['namespace'] = target_namespace

        # Remove status field
        resource.pop('status', None)

        kind = resource.get('kind')

        # Image registry rewrite for workloads
        try:
            if registry_rewrite and kind in ['Deployment', 'StatefulSet', 'Job', 'CronJob', 'DeploymentConfig']:
                containers: List[Dict[str, Any]] = []
                if kind in ['Deployment', 'StatefulSet', 'DeploymentConfig']:
                    containers = resource.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                elif kind == 'Job':
                    containers = resource.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                elif kind == 'CronJob':
                    containers = resource.get('spec', {}).get('jobTemplate', {}).get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
                for c in containers:
                    image = c.get('image')
                    if image:
                        image_name = image.split('/')[-1]
                        c['image'] = f"{registry_rewrite.rstrip('/')}/{image_name}"
        except Exception:
            pass

        # Service: strip clusterIP/clusterIPs
        if kind == 'Service':
            spec = resource.get('spec', {})
            spec.pop('clusterIP', None)
            spec.pop('clusterIPs', None)

        # PVC: map storageClassName if needed (user must review)
        if kind == 'PersistentVolumeClaim':
            spec = resource.get('spec', {})
            # Optionally map storageClassName here
            # For now, just warn in docs

        # Secret: attempt to transform image pull secrets for ACR
        if kind == 'Secret' and resource.get('type') == 'kubernetes.io/dockerconfigjson':
            # If registry_rewrite is set, rewrite .dockerconfigjson
            import base64, json as js
            data = resource.get('data', {})
            if '.dockerconfigjson' in data and registry_rewrite:
                try:
                    decoded = base64.b64decode(data['.dockerconfigjson']).decode('utf-8')
                    config_json = js.loads(decoded)
                    # Overwrite all registry keys with the new registry
                    auths = config_json.get('auths', {})
                    new_auths = {}
                    for reg in auths:
                        new_auths[registry_rewrite] = auths[reg]
                        break  # Only keep one
                    config_json['auths'] = new_auths
                    encoded = base64.b64encode(js.dumps(config_json).encode('utf-8')).decode('utf-8')
                    data['.dockerconfigjson'] = encoded
                except Exception:
                    pass

        # DeploymentConfig: convert to Deployment (basic)
        if kind == 'DeploymentConfig':
            # Minimal conversion: treat as Deployment, drop OpenShift triggers, etc.
            resource['kind'] = 'Deployment'
            resource['apiVersion'] = 'apps/v1'
            # Remove OpenShift-specific fields
            for field in ['triggers', 'strategy', 'test', 'paused']:
                resource.get('spec', {}).pop(field, None)

        # CronJob: ensure apiVersion is correct for AKS
        if kind == 'CronJob':
            resource['apiVersion'] = 'batch/v1'

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
    
    def migrate_application(self, namespace: str, output_dir: str, apply: bool = False,
                             registry_rewrite: Optional[str] = None,
                             target_namespace: Optional[str] = None,
                             acr_env_path: Optional[str] = None) -> bool:
        """
        Migrate application from OpenShift to AKS
        
        Args:
            namespace: Source namespace
            output_dir: Directory to save transformed resources
            apply: Whether to apply resources to target cluster
            registry_rewrite: ACR login server (e.g. myacr.azurecr.io) to rewrite images
            target_namespace: Target namespace (defaults to source)
            acr_env_path: Path to .env file containing ACR credentials for image import
            
        Returns:
            True if successful, False otherwise
        """
        # Load ACR credentials from .env if provided
        acr_name: Optional[str] = None
        acr_login_server: Optional[str] = None
        acr_username: Optional[str] = None
        acr_password: Optional[str] = None
        ghcr_username: Optional[str] = os.getenv('GHCR_USERNAME')
        ghcr_token: Optional[str] = os.getenv('GHCR_TOKEN')
        if acr_env_path and Path(acr_env_path).exists():
            self.logger.info(f"Loading ACR credentials from {acr_env_path}")
            with open(acr_env_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    if '=' in line:
                        key, val = line.split('=', 1)
                        if key == 'ACR_NAME':
                            acr_name = val
                        elif key == 'ACR_LOGIN_SERVER':
                            acr_login_server = val
                        elif key == 'ACR_ADMIN_USERNAME':
                            acr_username = val
                        elif key == 'ACR_ADMIN_PASSWORD':
                            acr_password = val
                        elif key == 'GHCR_USERNAME' and not ghcr_username:
                            ghcr_username = val
                        elif key == 'GHCR_TOKEN' and not ghcr_token:
                            ghcr_token = val
            # If registry_rewrite not set and ACR login server is available, use it
            if not registry_rewrite and acr_login_server:
                registry_rewrite = acr_login_server
                self.logger.info(f"Using ACR_LOGIN_SERVER from .env: {registry_rewrite}")

        # First, document the application
        export_data = self.document_application(namespace, f"{output_dir}/source")
        
        # Create output directory for AKS manifests
        aks_output = Path(output_dir) / 'aks'
        aks_output.mkdir(parents=True, exist_ok=True)
        
        source_dir = Path(output_dir) / 'source'
        
        # ACR image import logic
        if acr_name and acr_login_server:
            self.logger.info("ACR context found. Extracting images from manifests for import.")
            images = self.extract_images_from_manifests(source_dir)
            if images:
                self.logger.info(f"Found {len(images)} unique image(s) in manifests: {images}")
                self.logger.info("Importing images to ACR (with GHCR auth if provided)...")
                self.import_images_to_acr(images, acr_login_server, acr_name, ghcr_username, ghcr_token)
                self.logger.info("Rewriting source manifests to use ACR image paths.")
                self.rewrite_images_for_acr(source_dir, acr_login_server)
                self.logger.info("Image import & rewrite phase complete.")
            else:
                self.logger.info("No images found in manifests.")
        else:
            if acr_env_path:
                self.logger.warning("ACR details incomplete. Skipping image import.")

        # Transform Deployments
        if (source_dir / 'deployments.yaml').exists():
            with open(source_dir / 'deployments.yaml', 'r') as f:
                deployments = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(d, registry_rewrite, target_namespace) for d in deployments if d]
            with open(aks_output / 'deployments.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform StatefulSets
        if (source_dir / 'statefulsets.yaml').exists():
            with open(source_dir / 'statefulsets.yaml', 'r') as f:
                statefulsets = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(s, registry_rewrite, target_namespace) for s in statefulsets if s]
            with open(aks_output / 'statefulsets.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform Jobs
        if (source_dir / 'jobs.yaml').exists():
            with open(source_dir / 'jobs.yaml', 'r') as f:
                jobs = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(j, registry_rewrite, target_namespace) for j in jobs if j]
            with open(aks_output / 'jobs.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform CronJobs
        if (source_dir / 'cronjobs.yaml').exists():
            with open(source_dir / 'cronjobs.yaml', 'r') as f:
                cronjobs = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(cj, registry_rewrite, target_namespace) for cj in cronjobs if cj]
            with open(aks_output / 'cronjobs.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform PVCs
        if (source_dir / 'pvcs.yaml').exists():
            with open(source_dir / 'pvcs.yaml', 'r') as f:
                pvcs = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(pvc, registry_rewrite, target_namespace) for pvc in pvcs if pvc]
            with open(aks_output / 'pvcs.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform ServiceAccounts
        if (source_dir / 'serviceaccounts.yaml').exists():
            with open(source_dir / 'serviceaccounts.yaml', 'r') as f:
                sas = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(sa, registry_rewrite, target_namespace) for sa in sas if sa]
            with open(aks_output / 'serviceaccounts.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform DeploymentConfigs (convert to Deployments)
        if (source_dir / 'deploymentconfigs.yaml').exists():
            with open(source_dir / 'deploymentconfigs.yaml', 'r') as f:
                dcs = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(dc, registry_rewrite, target_namespace) for dc in dcs if dc]
            with open(aks_output / 'deployments-from-dc.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform Services
        if (source_dir / 'services.yaml').exists():
            with open(source_dir / 'services.yaml', 'r') as f:
                services = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(s, registry_rewrite, target_namespace) for s in services if s]
            with open(aks_output / 'services.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform ConfigMaps
        if (source_dir / 'configmaps.yaml').exists():
            with open(source_dir / 'configmaps.yaml', 'r') as f:
                configmaps = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(cm, registry_rewrite, target_namespace) for cm in configmaps if cm]
            with open(aks_output / 'configmaps.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)

        # Transform Routes to Ingress
        if (source_dir / 'routes.yaml').exists():
            with open(source_dir / 'routes.yaml', 'r') as f:
                routes = list(yaml.safe_load_all(f))
            ingresses = [self.route_to_ingress(route) for route in routes if route]
            if ingresses:
                with open(aks_output / 'ingresses.yaml', 'w') as f:
                    yaml.dump_all(ingresses, f, default_flow_style=False)

        # Transform Secrets (with ACR logic)
        if (source_dir / 'secrets.yaml').exists():
            with open(source_dir / 'secrets.yaml', 'r') as f:
                secrets = list(yaml.safe_load_all(f))
            transformed = [self.transform_resource(s, registry_rewrite, target_namespace) for s in secrets if s]
            with open(aks_output / 'secrets.yaml', 'w') as f:
                yaml.dump_all(transformed, f, default_flow_style=False)
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
    doc_parser.add_argument('--namespace', help='OpenShift namespace/project')
    doc_parser.add_argument('--output', help='Output directory for exported resources')
    doc_parser.add_argument('--context', help='Kubernetes context for OpenShift cluster')

    # Migrate command
    migrate_parser = subparsers.add_parser('migrate', help='Migrate application from OpenShift to AKS')
    migrate_parser.add_argument('--namespace', help='Source namespace')
    migrate_parser.add_argument('--source-context', help='Kubernetes context for OpenShift cluster')
    migrate_parser.add_argument('--target-context', help='Kubernetes context for AKS cluster')
    migrate_parser.add_argument('--output', help='Output directory for migrated resources')
    migrate_parser.add_argument('--apply', action='store_true', help='Apply resources to AKS')
    migrate_parser.add_argument('--registry-rewrite', help='Rewrite container image registry (e.g. myregistry.azurecr.io)')
    migrate_parser.add_argument('--target-namespace', help='Namespace to use on AKS (defaults to source)')
    migrate_parser.add_argument('--acr-env-path', help='Path to .env file with ACR credentials (for image import)')

    # Global options
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')

    args = parser.parse_args()

    # Interactive prompt for missing required arguments
    # TODO: For each required argument, if not provided, prompt the user interactively
    # Example: if not args.namespace: args.namespace = input('Enter namespace: ')
    # For now, just print a warning if missing
    if args.command == 'document':
        if not args.namespace:
            args.namespace = input('Enter OpenShift namespace/project: ')
        if not args.output:
            args.output = input('Enter output directory for exported resources: ')
    elif args.command == 'migrate':
        if not args.namespace:
            args.namespace = input('Enter source namespace: ')
        if not args.output:
            args.output = input('Enter output directory for migrated resources: ')
        if not args.source_context:
            args.source_context = input('Enter Kubernetes context for OpenShift cluster (blank for default): ')
        if not args.target_context:
            args.target_context = input('Enter Kubernetes context for AKS cluster (blank for default): ')
        if not args.target_namespace:
            confirm = input(f'Use source namespace "{args.namespace}" as target namespace on AKS? [Y/n]: ')
            if confirm.lower() in ('n', 'no'):
                args.target_namespace = input('Enter target namespace for AKS: ')
            else:
                args.target_namespace = args.namespace

    # Check if kubernetes is available when executing commands
    if args.command and not KUBERNETES_AVAILABLE:
        print("Error: kubernetes package not found. Please run: pip install -r requirements.txt", file=sys.stderr)
        sys.exit(1)

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
        # Confirm before applying if --apply is set
        if args.apply:
            confirm = input('Are you sure you want to apply these resources to AKS? [y/N]: ')
            if confirm.lower() not in ('y', 'yes'):
                print('Aborting apply.')
                sys.exit(0)
        success = migrator.migrate_application(args.namespace, args.output, args.apply,
                               registry_rewrite=args.registry_rewrite,
                               target_namespace=args.target_namespace or args.namespace,
                               acr_env_path=args.acr_env_path)
        if not success:
            sys.exit(1)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
