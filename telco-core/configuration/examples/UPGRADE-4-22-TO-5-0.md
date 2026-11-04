# OpenShift 4.22 to 5.0 Core Cluster Upgrade Procedure

This document describes the automated upgrade procedure for Core clusters from OpenShift 4.22 to 5.0 using ACM policies and TALM (Topology Aware Lifecycle Manager).

## Overview

The upgrade from 4.22 to 5.0 is an EUS-to-EUS (Extended Update Support) upgrade that follows a two-phase control plane upgrade followed by worker node upgrade:

1. **Phase 1**: Upgrade control plane from current version to 4.22
2. **Phase 2**: Upgrade control plane from 4.22 to 5.0 (workers remain paused)
3. **Phase 3**: Unpause and upgrade worker nodes to 5.0

## Prerequisites

### Infrastructure Requirements
- Multi-Node OpenShift (MNO) bare metal cluster
- 3 control plane nodes
- 2+ worker nodes
- Multiple MachineConfigPools (MCPs) for worker partitioning
- ACM hub cluster with TALM operator installed

### Policy Configuration
The following policy sets must be available in the ACM hub:

**For 4.22:**
- `core-upgrade-precache-4-22.yaml` (optional)
- `core-upgrade-4-22.yaml`

**For 5.0:**
- `core-upgrade-precache-5-0.yaml` (optional)
- `core-upgrade.yaml` (contains 5-0 policies)

**Version-agnostic:**
- `core-upgrade-finish.yaml`

## Upgrade Steps

### Step 1: Prepare Image Mirror (if using disconnected environment)

Use the `rds-update-prepare.yaml` playbook to mirror release images:

```bash
ansible-playbook rds-update-prepare.yaml \
  -e kubeconfig_spoke=/path/to/spoke/kubeconfig \
  -e ocp_image_one_url=quay.io/openshift-release-dev/ocp-release:4.22.0-x86_64 \
  -e ocp_image_two_url=quay.io/openshift-release-dev/ocp-release:5.0.0-x86_64 \
  -e local_registry_host_name=registry.example.com \
  -e local_registry_host_port=5000 \
  -e rds_generate_pinned_imageset=true \
  -e rds_create_update_params_cm=true
```

### Step 2: (Optional) Pre-cache Images

Pre-caching reduces upgrade maintenance window by pulling images ahead of time.

1. Label the cluster to activate pre-caching:
```bash
oc label managedcluster <cluster-name> upgrade-precache=""
```

2. Create and enable the pre-cache CGU:
```yaml
apiVersion: ran.openshift.io/v1alpha1
kind: ClusterGroupUpgrade
metadata:
  name: upgrade-precache
  namespace: default
spec:
  clusters:
  - <cluster-name>
  enable: true
  managedPolicies:
    - core-upgrade-precache-controlplane-4-22
    - core-upgrade-precache-worker-4-22
    - core-upgrade-precache-validator-4-22
    - core-upgrade-precache-controlplane-5-0
    - core-upgrade-precache-worker-5-0
    - core-upgrade-precache-validator-5-0
  remediationStrategy:
    maxConcurrency: 1
    timeout: 240
```

3. Wait for pre-caching to complete:
```bash
oc get cgu upgrade-precache -n default -w
```

### Step 3: Upgrade Control Plane to 4.22

1. Label the cluster for 4.22 upgrade:
```bash
oc label managedcluster <cluster-name> upgrade-version-4-22=""
```

2. Create and enable the 4.22 upgrade CGU:
```yaml
apiVersion: ran.openshift.io/v1alpha1
kind: ClusterGroupUpgrade
metadata:
  name: upgrade-4-22
  namespace: default
spec:
  actions:
    afterCompletion:
      deleteClusterLabels:
        upgrade-version-4-22: ""
      deleteObjects: true
  clusters:
  - <cluster-name>
  enable: true
  managedPolicies:
    - core-upgrade-prep-4-22
    - core-upgrade-ocp-4-22
    - core-upgrade-olm-4-22
    - core-upgrade-validate-4-22
  remediationStrategy:
    maxConcurrency: 1
    timeout: 480
```

3. Monitor the upgrade:
```bash
oc get cgu upgrade-4-22 -n default -w
```

### Step 4: Upgrade Control Plane to 5.0

1. After 4.22 upgrade completes, label the cluster for 5.0:
```bash
oc label managedcluster <cluster-name> upgrade-version-5-0=""
```

2. Create and enable the 5.0 upgrade CGU:
```yaml
apiVersion: ran.openshift.io/v1alpha1
kind: ClusterGroupUpgrade
metadata:
  name: upgrade-5-0
  namespace: default
spec:
  actions:
    afterCompletion:
      deleteClusterLabels:
        upgrade-version-5-0: ""
      deleteObjects: true
  clusters:
  - <cluster-name>
  enable: true
  managedPolicies:
    - core-upgrade-prep-5-0
    - core-upgrade-ocp-5-0
    - core-upgrade-olm-5-0
    - core-upgrade-validate-5-0
  remediationStrategy:
    maxConcurrency: 1
    timeout: 480
  blockingCRs:
  - name: upgrade-4-22
    namespace: default
```

3. Monitor the upgrade:
```bash
oc get cgu upgrade-5-0 -n default -w
```

### Step 5: Upgrade Worker Nodes

1. After 5.0 control plane upgrade completes, label the cluster for worker upgrade:
```bash
oc label managedcluster <cluster-name> upgrade-finish=""
```

2. Create and enable the worker upgrade CGU:
```yaml
apiVersion: ran.openshift.io/v1alpha1
kind: ClusterGroupUpgrade
metadata:
  name: upgrade-finish
  namespace: default
spec:
  clusters:
  - <cluster-name>
  enable: true
  managedPolicies:
    - core-upgrade-workers-1
    - core-upgrade-workers-2
    - core-upgrade-workers-3
  remediationStrategy:
    maxConcurrency: 1
    timeout: 480
  blockingCRs:
  - name: upgrade-5-0
    namespace: default
```

3. Monitor the worker upgrade:
```bash
oc get cgu upgrade-finish -n default -w
```

### Step 6: Verify Upgrade Completion

1. Check cluster version:
```bash
oc get clusterversion
```

2. Verify all nodes are updated:
```bash
oc get nodes
```

3. Check all MCPs are updated:
```bash
oc get mcp
```

4. Verify operator subscriptions:
```bash
oc get subscription -A
```

## Validation Checklist

- [ ] Upgrade completes with no manual intervention
- [ ] All control plane nodes upgraded to 5.0
- [ ] All worker nodes upgraded to 5.0
- [ ] All MCPs show Updated=True, Updating=False
- [ ] All operator subscriptions at AtLatestKnown
- [ ] No pods in CrashLoopBackOff
- [ ] Application workloads functional

## Rollback Procedure

If issues occur during upgrade:

1. **During control plane upgrade**: Contact Red Hat support - rolling back a control plane upgrade is not supported
2. **Before worker upgrade**: Keep worker MCPs paused and investigate control plane issues
3. **During worker upgrade**: Individual worker nodes can be recovered by re-imaging if necessary

## Automation with Ansible

The complete upgrade can be orchestrated using the `rds-update.yaml` playbook:

```bash
ansible-playbook rds-update.yaml \
  -e kubeconfig_hub=/path/to/hub/kubeconfig \
  -e kubeconfig_spoke=/path/to/spoke/kubeconfig \
  -e managedcluster_name=<cluster-name> \
  -e managedcluster_1st_update_label_key=upgrade-version-4-22 \
  -e managedcluster_1st_update_label_value="" \
  -e managedcluster_2nd_update_label_key=upgrade-version-5-0 \
  -e managedcluster_2nd_update_label_value="" \
  -e managedcluster_3d_update_label_key=upgrade-finish \
  -e managedcluster_3d_update_label_value="" \
  -e policies_1st_update='[{"name": "core-upgrade-prep-4-22", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-ocp-4-22", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-olm-4-22", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-validate-4-22", "policy_namespace": "default", "cgu_remediation_timeout": 480}]' \
  -e policies_2nd_update='[{"name": "core-upgrade-prep-5-0", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-ocp-5-0", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-olm-5-0", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-validate-5-0", "policy_namespace": "default", "cgu_remediation_timeout": 480}]' \
  -e policies_compute_update='[{"name": "core-upgrade-workers-1", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-workers-2", "policy_namespace": "default", "cgu_remediation_timeout": 480}, {"name": "core-upgrade-workers-3", "policy_namespace": "default", "cgu_remediation_timeout": 480}]'
```

## References

- [Telco Core Configuration](../../configuration/README.md)
- [ACM Policy Generator](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.14/html/governance/policy-deployment#policy-generator)
- [TALM Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/scalability_and_performance/using-topology-aware-lifecycle-manager-to-provision-managed-clusters)
