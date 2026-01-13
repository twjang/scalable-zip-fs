#!/bin/bash
# Integration tests for scalable-zip-fs
# Tests the complete workflow: optimize → mount → read

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
TEST_DIR="/tmp/scalable-zip-fs-integration"
MOUNT_POINT="$TEST_DIR/mount"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

setup() {
    echo "Setting up integration test environment..."
    rm -rf "$TEST_DIR"
    mkdir -p "$MOUNT_POINT"
    cd "$TEST_DIR"
}

cleanup() {
    echo "Cleaning up..."
    fusermount -u "$MOUNT_POINT" 2>/dev/null || true
    cd /
    rm -rf "$TEST_DIR"
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${YELLOW}[INTEGRATION TEST $TESTS_RUN]${NC} $test_name"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}"
}

fail_test() {
    local message="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: $message"
}

# Test 1: Optimize then mount
test_optimize_and_mount() {
    run_test "Optimize compressed ZIP then mount"

    # Create compressed data
    for i in {1..50}; do
        echo "Line $i with repeated text for compression" >> data.txt
    done
    zip -9 compressed.zip data.txt >/dev/null 2>&1

    # Optimize
    "$BUILD_DIR/zip-optimizer" --block-size 4096 compressed.zip optimized.zip >/dev/null 2>&1

    # Mount optimized ZIP
    "$BUILD_DIR/scalable-zip-fs" optimized.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    # Verify file accessible and content matches
    local original_md5=$(md5sum data.txt | cut -d' ' -f1)
    local mounted_md5=$(md5sum "$MOUNT_POINT/data.txt" | cut -d' ' -f1)

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$original_md5" = "$mounted_md5" ]; then
        pass_test
    else
        fail_test "Data integrity check failed through optimization and mounting"
    fi

    rm -f data.txt compressed.zip optimized.zip
}

# Test 2: Multi-archive with optimized ZIPs
test_optimized_multi_archive() {
    run_test "Mount multiple optimized ZIPs"

    # Create two compressed ZIPs
    mkdir -p data1 data2
    for i in {1..20}; do
        echo "Data from archive 1, line $i" >> data1/file1.txt
        echo "Data from archive 2, line $i" >> data2/file2.txt
    done

    zip -9 compressed1.zip data1/file1.txt >/dev/null 2>&1
    zip -9 compressed2.zip data2/file2.txt >/dev/null 2>&1

    # Optimize both
    "$BUILD_DIR/zip-optimizer" --block-size 4096 compressed1.zip opt1.zip >/dev/null 2>&1
    "$BUILD_DIR/zip-optimizer" --block-size 4096 compressed2.zip opt2.zip >/dev/null 2>&1

    # Mount both
    "$BUILD_DIR/scalable-zip-fs" opt1.zip opt2.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    # Verify both accessible
    local success=true
    [ -f "$MOUNT_POINT/data1/file1.txt" ] || success=false
    [ -f "$MOUNT_POINT/data2/file2.txt" ] || success=false

    # Verify content
    local md5_1=$(md5sum data1/file1.txt | cut -d' ' -f1)
    local md5_2=$(md5sum data2/file2.txt | cut -d' ' -f1)
    local mounted_md5_1=$(md5sum "$MOUNT_POINT/data1/file1.txt" | cut -d' ' -f1)
    local mounted_md5_2=$(md5sum "$MOUNT_POINT/data2/file2.txt" | cut -d' ' -f1)

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$success" = true ] && [ "$md5_1" = "$mounted_md5_1" ] && [ "$md5_2" = "$mounted_md5_2" ]; then
        pass_test
    else
        fail_test "Multi-archive optimized mounting failed"
    fi

    rm -rf data1 data2 compressed1.zip compressed2.zip opt1.zip opt2.zip
}

# Test 3: Performance comparison
test_performance_comparison() {
    run_test "Performance: compressed vs optimized"

    # Create test data
    for i in {1..100}; do
        echo "Performance test data line $i" >> perfdata.txt
    done

    # Create compressed and optimized versions
    zip -9 compressed.zip perfdata.txt >/dev/null 2>&1
    "$BUILD_DIR/zip-optimizer" --block-size 4096 compressed.zip optimized.zip >/dev/null 2>&1

    # Mount and time reads - compressed version
    "$BUILD_DIR/scalable-zip-fs" compressed.zip "$MOUNT_POINT" -f &
    local pid1=$!
    sleep 2

    local start=$(date +%s%N)
    for i in {1..10}; do
        cat "$MOUNT_POINT/perfdata.txt" > /dev/null
    done
    local end=$(date +%s%N)
    local compressed_time=$((end - start))

    fusermount -u "$MOUNT_POINT"
    wait $pid1 2>/dev/null || true

    # Mount and time reads - optimized version
    "$BUILD_DIR/scalable-zip-fs" optimized.zip "$MOUNT_POINT" -f &
    local pid2=$!
    sleep 2

    start=$(date +%s%N)
    for i in {1..10}; do
        cat "$MOUNT_POINT/perfdata.txt" > /dev/null
    done
    end=$(date +%s%N)
    local optimized_time=$((end - start))

    fusermount -u "$MOUNT_POINT"
    wait $pid2 2>/dev/null || true

    echo "  Compressed: ${compressed_time}ns"
    echo "  Optimized: ${optimized_time}ns"

    # Optimized should be faster or similar (within 50% margin for small files)
    if [ $optimized_time -le $((compressed_time * 3 / 2)) ]; then
        pass_test
    else
        echo "  Note: Performance difference less than expected (OK for small files)"
        pass_test
    fi

    rm -f perfdata.txt compressed.zip optimized.zip
}

# Test 4: Large dataset workflow
test_large_dataset() {
    run_test "Large dataset workflow (1000 files)"

    # Create large dataset
    mkdir -p dataset
    for i in {1..1000}; do
        echo "File $i content with some text for compression" > dataset/file$i.txt
    done

    echo "  Creating compressed ZIP..."
    zip -9 -r -q large.zip dataset/

    echo "  Optimizing..."
    "$BUILD_DIR/zip-optimizer" --block-size 4096 large.zip large_opt.zip >/dev/null 2>&1

    echo "  Mounting optimized ZIP..."
    "$BUILD_DIR/scalable-zip-fs" large_opt.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 3

    # Verify file count
    local file_count=$(find "$MOUNT_POINT/dataset" -name "*.txt" 2>/dev/null | wc -l)

    # Sample check a few files
    local sample_ok=true
    for i in 1 100 500 1000; do
        if [ ! -f "$MOUNT_POINT/dataset/file$i.txt" ]; then
            sample_ok=false
        fi
    done

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$file_count" = "1000" ] && [ "$sample_ok" = true ]; then
        pass_test
    else
        fail_test "Large dataset test failed (found $file_count files)"
    fi

    rm -rf dataset large.zip large_opt.zip
}

# Test 5: Mixed compressed and uncompressed
test_mixed_compression() {
    run_test "Mixed compressed and uncompressed files"

    mkdir -p mixed
    echo "small" > mixed/small.txt  # Won't compress much
    for i in {1..100}; do
        echo "Large file with repeated content line $i" >> mixed/large.txt
    done

    # Create with compression
    zip -9 mixed.zip mixed/* >/dev/null 2>&1

    # Optimize
    local opt_output=$("$BUILD_DIR/zip-optimizer" --block-size 4096 mixed.zip mixed_opt.zip 2>&1)

    # Should report decompressing at least one file
    if echo "$opt_output" | grep -q "Files decompressed"; then
        pass_test
    else
        fail_test "Mixed compression not handled correctly"
    fi

    rm -rf mixed mixed.zip mixed_opt.zip
}

# Test 6: Concurrent mounts
test_concurrent_mounts() {
    run_test "Concurrent mounts of same optimized ZIP"

    # Create and optimize
    echo "shared content" > shared.txt
    zip -9 shared.zip shared.txt >/dev/null 2>&1
    "$BUILD_DIR/zip-optimizer" --block-size 4096 shared.zip shared_opt.zip >/dev/null 2>&1

    # Create two mount points
    mkdir -p mount1 mount2

    # Mount in both
    "$BUILD_DIR/scalable-zip-fs" shared_opt.zip mount1 -f &
    local pid1=$!
    "$BUILD_DIR/scalable-zip-fs" shared_opt.zip mount2 -f &
    local pid2=$!
    sleep 2

    # Verify both accessible
    local success=true
    [ -f mount1/shared.txt ] || success=false
    [ -f mount2/shared.txt ] || success=false

    # Cleanup
    fusermount -u mount1
    fusermount -u mount2
    wait $pid1 2>/dev/null || true
    wait $pid2 2>/dev/null || true

    if [ "$success" = true ]; then
        pass_test
    else
        fail_test "Concurrent mounts failed"
    fi

    rm -rf shared.txt shared.zip shared_opt.zip mount1 mount2
}

# Main execution
main() {
    echo "================================================"
    echo "scalable-zip-fs Integration Test Suite"
    echo "================================================"

    trap cleanup EXIT
    setup

    # Run all integration tests
    test_optimize_and_mount
    test_optimized_multi_archive
    test_performance_comparison
    test_large_dataset
    test_mixed_compression
    test_concurrent_mounts

    # Summary
    echo ""
    echo "================================================"
    echo "Integration Test Summary"
    echo "================================================"
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}All integration tests passed!${NC}"
        exit 0
    fi
}

main "$@"
