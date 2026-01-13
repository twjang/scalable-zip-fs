#!/bin/bash
# Master test runner for scalable-zip-fs project
# Runs all test suites and generates a summary report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test suite results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo "================================================"
echo "scalable-zip-fs Complete Test Suite"
echo "================================================"
echo ""

# Check if build exists
if [ ! -f "$SCRIPT_DIR/../build/scalable-zip-fs" ]; then
    echo -e "${RED}Error: scalable-zip-fs not built. Run 'meson compile -C build' first.${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/../build/scalable-zip-optimize" ]; then
    echo -e "${RED}Error: scalable-zip-optimize not built. Run 'meson compile -C build' first.${NC}"
    exit 1
fi

run_suite() {
    local suite_name="$1"
    local suite_script="$2"

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Running: $suite_name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if "$suite_script"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo -e "\n${GREEN}✓ $suite_name PASSED${NC}\n"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        echo -e "\n${RED}✗ $suite_name FAILED${NC}\n"
    fi
}

# Run all test suites
run_suite "Filesystem Tests" "$SCRIPT_DIR/test_filesystem.sh"
run_suite "ZIP Optimizer Tests" "$SCRIPT_DIR/test_optimizer.sh"
run_suite "Integration Tests" "$SCRIPT_DIR/test_integration.sh"

# Final summary
echo "================================================"
echo "FINAL TEST SUMMARY"
echo "================================================"
echo "Test suites run: $TOTAL_SUITES"
echo -e "${GREEN}Suites passed: $PASSED_SUITES${NC}"

if [ $FAILED_SUITES -gt 0 ]; then
    echo -e "${RED}Suites failed: $FAILED_SUITES${NC}"
    echo ""
    echo -e "${RED}TEST RUN FAILED${NC}"
    exit 1
else
    echo "Suites failed: 0"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}       ALL TESTS PASSED SUCCESSFULLY!        ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi
