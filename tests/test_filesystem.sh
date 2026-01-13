#!/bin/bash
# Test suite for scalable-zip-fs filesystem
# Tests basic mounting, reading, and unmounting functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
TEST_DIR="/tmp/scalable-zip-fs-tests"
MOUNT_POINT="$TEST_DIR/mount"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup
setup() {
    echo "Setting up test environment..."
    rm -rf "$TEST_DIR"
    mkdir -p "$MOUNT_POINT"
    cd "$TEST_DIR"
}

# Cleanup
cleanup() {
    echo "Cleaning up..."
    fusermount -u "$MOUNT_POINT" 2>/dev/null || true
    cd /
    rm -rf "$TEST_DIR"
}

# Test helper functions
run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "\n${YELLOW}[TEST $TESTS_RUN]${NC} $test_name"
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

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values don\'t match}"

    if [ "$expected" = "$actual" ]; then
        return 0
    else
        fail_test "$message (expected: '$expected', got: '$actual')"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    if [ -f "$file" ]; then
        return 0
    else
        fail_test "File does not exist: $file"
        return 1
    fi
}

assert_file_content() {
    local file="$1"
    local expected_content="$2"
    local actual_content
    actual_content=$(cat "$file")
    assert_equals "$expected_content" "$actual_content" "File content mismatch for $file"
}

# Test 1: Mount single ZIP file
test_mount_single_zip() {
    run_test "Mount single ZIP file"

    # Create test ZIP
    mkdir -p testdata
    echo "Hello World" > testdata/file.txt
    zip -q test.zip testdata/file.txt

    # Mount
    "$BUILD_DIR/scalable-zip-fs" test.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    # Verify
    if [ -f "$MOUNT_POINT/testdata/file.txt" ]; then
        local content=$(cat "$MOUNT_POINT/testdata/file.txt")
        fusermount -u "$MOUNT_POINT"
        wait $pid 2>/dev/null || true

        if [ "$content" = "Hello World" ]; then
            pass_test
        else
            fail_test "File content incorrect"
        fi
    else
        fusermount -u "$MOUNT_POINT" 2>/dev/null || true
        wait $pid 2>/dev/null || true
        fail_test "Mounted file not accessible"
    fi

    rm -rf testdata test.zip
}

# Test 2: Read-only enforcement
test_readonly_enforcement() {
    run_test "Read-only filesystem enforcement"

    # Create test ZIP
    mkdir -p testdata
    echo "test" > testdata/file.txt
    zip -q test.zip testdata/file.txt

    # Mount
    "$BUILD_DIR/scalable-zip-fs" test.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    # Try to write (should fail)
    if echo "write attempt" > "$MOUNT_POINT/testdata/newfile.txt" 2>/dev/null; then
        fusermount -u "$MOUNT_POINT"
        wait $pid 2>/dev/null || true
        fail_test "Write operation succeeded when it should have failed"
    else
        fusermount -u "$MOUNT_POINT"
        wait $pid 2>/dev/null || true
        pass_test
    fi

    rm -rf testdata test.zip
}

# Test 3: Directory traversal
test_directory_traversal() {
    run_test "Directory traversal"

    # Create nested structure
    mkdir -p testdata/dir1/dir2
    echo "file1" > testdata/file1.txt
    echo "file2" > testdata/dir1/file2.txt
    echo "file3" > testdata/dir1/dir2/file3.txt
    zip -q -r test.zip testdata/

    # Mount
    "$BUILD_DIR/scalable-zip-fs" test.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    # Verify structure
    local success=true
    [ -d "$MOUNT_POINT/testdata/dir1/dir2" ] || success=false
    [ -f "$MOUNT_POINT/testdata/file1.txt" ] || success=false
    [ -f "$MOUNT_POINT/testdata/dir1/file2.txt" ] || success=false
    [ -f "$MOUNT_POINT/testdata/dir1/dir2/file3.txt" ] || success=false

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$success" = true ]; then
        pass_test
    else
        fail_test "Directory structure not correctly accessible"
    fi

    rm -rf testdata test.zip
}

# Test 4: Empty files
test_empty_files() {
    run_test "Empty files"

    mkdir -p testdata
    touch testdata/empty.txt
    zip -q test.zip testdata/empty.txt

    "$BUILD_DIR/scalable-zip-fs" test.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    if [ -f "$MOUNT_POINT/testdata/empty.txt" ]; then
        local size=$(stat -c%s "$MOUNT_POINT/testdata/empty.txt")
        fusermount -u "$MOUNT_POINT"
        wait $pid 2>/dev/null || true

        if [ "$size" = "0" ]; then
            pass_test
        else
            fail_test "Empty file has non-zero size: $size"
        fi
    else
        fusermount -u "$MOUNT_POINT" 2>/dev/null || true
        wait $pid 2>/dev/null || true
        fail_test "Empty file not accessible"
    fi

    rm -rf testdata test.zip
}

# Test 5: Large files
test_large_files() {
    run_test "Large files (10MB)"

    mkdir -p testdata
    dd if=/dev/urandom of=testdata/large.bin bs=1M count=10 2>/dev/null
    local original_md5=$(md5sum testdata/large.bin | cut -d' ' -f1)
    zip -q -0 test.zip testdata/large.bin

    "$BUILD_DIR/scalable-zip-fs" test.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    local mounted_md5=$(md5sum "$MOUNT_POINT/testdata/large.bin" | cut -d' ' -f1)

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$original_md5" = "$mounted_md5" ]; then
        pass_test
    else
        fail_test "File integrity check failed (MD5 mismatch)"
    fi

    rm -rf testdata test.zip
}

# Test 6: Special characters in filenames
test_special_characters() {
    run_test "Special characters in filenames"

    mkdir -p testdata
    echo "test" > "testdata/file with spaces.txt"
    echo "test" > "testdata/file-with-dashes.txt"
    echo "test" > "testdata/file_with_underscores.txt"
    zip -q test.zip testdata/*

    "$BUILD_DIR/scalable-zip-fs" test.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    local success=true
    [ -f "$MOUNT_POINT/testdata/file with spaces.txt" ] || success=false
    [ -f "$MOUNT_POINT/testdata/file-with-dashes.txt" ] || success=false
    [ -f "$MOUNT_POINT/testdata/file_with_underscores.txt" ] || success=false

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$success" = true ]; then
        pass_test
    else
        fail_test "Special character filenames not handled correctly"
    fi

    rm -rf testdata test.zip
}

# Test 7: Multi-archive mounting
test_multi_archive() {
    run_test "Multi-archive mounting"

    # Create two ZIPs with different files
    mkdir -p data1 data2
    echo "from zip1" > data1/file1.txt
    echo "from zip2" > data2/file2.txt
    zip -q zip1.zip data1/file1.txt
    zip -q zip2.zip data2/file2.txt

    "$BUILD_DIR/scalable-zip-fs" zip1.zip zip2.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    local success=true
    [ -f "$MOUNT_POINT/data1/file1.txt" ] || success=false
    [ -f "$MOUNT_POINT/data2/file2.txt" ] || success=false

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$success" = true ]; then
        pass_test
    else
        fail_test "Multi-archive files not accessible"
    fi

    rm -rf data1 data2 zip1.zip zip2.zip
}

# Test 8: File precedence in multi-archive
test_file_precedence() {
    run_test "File precedence (first ZIP wins)"

    # Create two ZIPs with same file path
    mkdir -p data
    echo "first" > data/conflict.txt
    zip -q first.zip data/conflict.txt
    echo "second" > data/conflict.txt
    zip -q second.zip data/conflict.txt

    "$BUILD_DIR/scalable-zip-fs" first.zip second.zip "$MOUNT_POINT" -f &
    local pid=$!
    sleep 2

    local content=$(cat "$MOUNT_POINT/data/conflict.txt")

    fusermount -u "$MOUNT_POINT"
    wait $pid 2>/dev/null || true

    if [ "$content" = "first" ]; then
        pass_test
    else
        fail_test "File precedence not working (expected 'first', got '$content')"
    fi

    rm -rf data first.zip second.zip
}

# Main execution
main() {
    echo "======================================"
    echo "scalable-zip-fs Filesystem Test Suite"
    echo "======================================"

    trap cleanup EXIT
    setup

    # Run all tests
    test_mount_single_zip
    test_readonly_enforcement
    test_directory_traversal
    test_empty_files
    test_large_files
    test_special_characters
    test_multi_archive
    test_file_precedence

    # Summary
    echo ""
    echo "======================================"
    echo "Test Summary"
    echo "======================================"
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
