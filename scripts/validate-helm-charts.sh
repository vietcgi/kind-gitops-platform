#!/bin/bash

# Helm Chart Validation Framework
# Validates all Helm charts for consistency, syntax, and best practices

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HELM_DIR="$PROJECT_DIR/helm"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}INFO${NC}: $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

FAILED_CHECKS=0
PASSED_CHECKS=0

echo "=========================================="
echo "Helm Chart Validation Framework"
echo "=========================================="
echo ""

# 1. SYNTAX VALIDATION
log_info "PHASE 1: Helm Syntax Validation"
echo ""

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")

    if [ ! -f "$chart_dir/Chart.yaml" ]; then
        log_warn "Skipping $chart_name (no Chart.yaml)"
        continue
    fi

    if helm lint "$chart_dir" > /dev/null 2>&1; then
        log_success "$chart_name: Syntax valid"
        ((PASSED_CHECKS++))
    else
        log_error "$chart_name: Syntax invalid"
        helm lint "$chart_dir" || true
        ((FAILED_CHECKS++))
    fi
done

echo ""

# 2. METADATA CONSISTENCY CHECK
log_info "PHASE 2: Metadata Consistency"
echo ""

missing_fields=0

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")
    chart_file="$chart_dir/Chart.yaml"

    if [ ! -f "$chart_file" ]; then continue; fi

    # Check for required fields
    checks=("apiVersion" "name" "version" "description" "type")
    missing=0

    for field in "${checks[@]}"; do
        if ! grep -q "^$field:" "$chart_file"; then
            log_warn "$chart_name: Missing field '$field' in Chart.yaml"
            ((missing++))
            ((missing_fields++))
        fi
    done

    if [ $missing -eq 0 ]; then
        log_success "$chart_name: All required fields present"
        ((PASSED_CHECKS++))
    else
        ((FAILED_CHECKS++))
    fi
done

echo ""

# 3. VALUES.YAML COMPLETENESS
log_info "PHASE 3: Values.yaml Completeness"
echo ""

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")
    values_file="$chart_dir/values.yaml"

    if [ ! -f "$values_file" ]; then
        log_warn "$chart_name: Missing values.yaml"
        ((FAILED_CHECKS++))
        continue
    fi

    # Check for essential values
    value_checks=("enabled" "image" "resources" "rbac")
    missing_values=0

    for value in "${value_checks[@]}"; do
        if ! grep -q "^${value}:" "$values_file"; then
            log_warn "$chart_name: Missing value '${value}' in values.yaml"
            ((missing_values++))
        fi
    done

    if [ $missing_values -eq 0 ]; then
        log_success "$chart_name: values.yaml is complete"
        ((PASSED_CHECKS++))
    else
        ((FAILED_CHECKS++))
    fi
done

echo ""

# 4. TEMPLATE DEPENDENCY CHECK
log_info "PHASE 4: Template Dependencies"
echo ""

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")
    chart_file="$chart_dir/Chart.yaml"

    if [ ! -f "$chart_file" ]; then continue; fi

    # Check if dependencies are declared vs actual usage
    if grep -q "^dependencies:" "$chart_file"; then
        if helm dependency list "$chart_dir" > /dev/null 2>&1; then
            log_success "$chart_name: Dependencies valid"
            ((PASSED_CHECKS++))
        else
            log_error "$chart_name: Dependency issues"
            ((FAILED_CHECKS++))
        fi
    else
        log_success "$chart_name: No dependencies declared"
        ((PASSED_CHECKS++))
    fi
done

echo ""

# 5. SECURITY CONTEXT CHECK
log_info "PHASE 5: Security Context Compliance"
echo ""

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")
    values_file="$chart_dir/values.yaml"

    if [ ! -f "$values_file" ]; then continue; fi

    # Skip falco (system agent needs elevated permissions)
    if [ "$chart_name" = "falco" ]; then
        log_success "$chart_name: System agent (elevated permissions allowed)"
        ((PASSED_CHECKS++))
        continue
    fi

    # Check for security context
    if grep -q "runAsNonRoot" "$values_file"; then
        if grep -q "runAsNonRoot: true" "$values_file"; then
            log_success "$chart_name: Security context enforced (non-root)"
            ((PASSED_CHECKS++))
        else
            log_warn "$chart_name: Running as root (security concern)"
            ((FAILED_CHECKS++))
        fi
    else
        log_warn "$chart_name: No runAsNonRoot defined"
        ((FAILED_CHECKS++))
    fi
done

echo ""

# 6. RESOURCE LIMITS CHECK
log_info "PHASE 6: Resource Limits Validation"
echo ""

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")
    values_file="$chart_dir/values.yaml"

    if [ ! -f "$values_file" ]; then continue; fi

    if grep -q "resources:" "$values_file"; then
        if grep -q "limits:" "$values_file"; then
            log_success "$chart_name: Resource limits defined"
            ((PASSED_CHECKS++))
        else
            log_warn "$chart_name: No resource limits defined"
            ((FAILED_CHECKS++))
        fi
    else
        log_warn "$chart_name: No resources section"
        ((FAILED_CHECKS++))
    fi
done

echo ""

# 7. NAMESPACE CONFIGURATION CHECK
log_info "PHASE 7: Namespace Configuration"
echo ""

for chart_dir in "$HELM_DIR"/*; do
    if [ ! -d "$chart_dir" ]; then continue; fi

    chart_name=$(basename "$chart_dir")
    namespace_template="$chart_dir/templates/namespace.yaml"

    if [ -f "$namespace_template" ]; then
        if grep -q "kind: Namespace" "$namespace_template"; then
            log_success "$chart_name: Namespace template present"
            ((PASSED_CHECKS++))
        else
            log_warn "$chart_name: Invalid namespace template"
            ((FAILED_CHECKS++))
        fi
    else
        log_warn "$chart_name: No namespace.yaml template"
        ((FAILED_CHECKS++))
    fi
done

echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""
echo -e "Passed Checks:  ${GREEN}${PASSED_CHECKS}${NC}"
echo -e "Failed Checks:  ${RED}${FAILED_CHECKS}${NC}"
echo ""

if [ $FAILED_CHECKS -eq 0 ]; then
    log_success "All validation checks passed!"
    exit 0
else
    log_error "Some validation checks failed. Please review above."
    exit 1
fi
