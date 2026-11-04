#!/bin/bash
# Extract image digests needed for 4.22 to 5.0 upgrade policies
# Usage: ./get-upgrade-digests.sh [4.22.x] [5.0.x]

set -euo pipefail

VERSION_422="${1:-4.22.0}"
VERSION_50="${2:-5.0.0}"

echo "=== Fetching image digests for upgrade policies ==="
echo ""

echo "## OCP Release Images"
echo ""

echo "### 4.22 Release (${VERSION_422})"
OCP_422_DIGEST=$(oc adm release info "quay.io/openshift-release-dev/ocp-release:${VERSION_422}-x86_64" --output=json 2>/dev/null | jq -r '.digest' || echo "ERROR: Could not fetch 4.22 digest")
OCP_422_PULLSPEC="quay.io/openshift-release-dev/ocp-release@${OCP_422_DIGEST}"
echo "Digest: ${OCP_422_DIGEST}"
echo "Pullspec: ${OCP_422_PULLSPEC}"
echo ""

echo "### 5.0 Release (${VERSION_50})"
OCP_50_DIGEST=$(oc adm release info "quay.io/openshift-release-dev/ocp-release:${VERSION_50}-x86_64" --output=json 2>/dev/null | jq -r '.digest' || echo "ERROR: Could not fetch 5.0 digest")
OCP_50_PULLSPEC="quay.io/openshift-release-dev/ocp-release@${OCP_50_DIGEST}"
echo "Digest: ${OCP_50_DIGEST}"
echo "Pullspec: ${OCP_50_PULLSPEC}"
echo ""

echo "## Operator Catalog Images"
echo ""

echo "### 4.22 Operator Index"
# For OLM operator catalog
CATALOG_422="registry.redhat.io/redhat/redhat-operator-index:v4.22"
CATALOG_422_DIGEST=$(skopeo inspect docker://${CATALOG_422} 2>/dev/null | jq -r '.Digest' || echo "ERROR: Could not fetch catalog digest (requires auth)")
echo "Digest: ${CATALOG_422_DIGEST}"
echo "Pullspec: registry.redhat.io/redhat/redhat-operator-index@${CATALOG_422_DIGEST}"
echo ""

echo "### 5.0 Operator Index"
CATALOG_50="registry.redhat.io/redhat/redhat-operator-index:v5.0"
CATALOG_50_DIGEST=$(skopeo inspect docker://${CATALOG_50} 2>/dev/null | jq -r '.Digest' || echo "ERROR: Could not fetch catalog digest (requires auth)")
echo "Digest: ${CATALOG_50_DIGEST}"
echo "Pullspec: registry.redhat.io/redhat/redhat-operator-index@${CATALOG_50_DIGEST}"
echo ""

echo "=== Update your policy files with these values ==="
echo ""
echo "For core-upgrade-4-22.yaml:"
echo "  spec.desiredUpdate.image: ${OCP_422_PULLSPEC}"
echo "  spec.image (catalog): registry.redhat.io/redhat/redhat-operator-index@${CATALOG_422_DIGEST}"
echo ""
echo "For core-upgrade.yaml (5.0):"
echo "  spec.desiredUpdate.image: ${OCP_50_PULLSPEC}"
echo "  spec.image (catalog): registry.redhat.io/redhat/redhat-operator-index@${CATALOG_50_DIGEST}"
echo ""

echo "For pre-cache policies, get all images from a release:"
echo "  oc adm release info ${OCP_422_PULLSPEC} --image-for=<component>"
echo "  or extract full image list:"
echo "  oc adm release info ${OCP_422_PULLSPEC} --contents | grep 'quay.io\\|registry.redhat.io'"
