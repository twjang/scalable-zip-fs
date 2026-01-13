#!/bin/bash
# Test suite for zip-optimizer tool
# Tests ZIP optimization functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
TEST_DIR="/tmp/zip-optimizer-tests"

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
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
}

# Cleanup
cleanup() {
    echo "Cleaning up..."
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

# Test 1: Help output
test_help_output() {
    run_test "Help output"

    if "$BUILD_DIR/zip-optimizer" --help | grep -q "block-size"; then
        pass_test
    else
        fail_test "Help output doesn't contain expected text"
    fi
}

# Test 2: Missing arguments
test_missing_arguments() {
    run_test "Missing arguments error"

    if "$BUILD_DIR/zip-optimizer" --block-size 4096 2>/dev/null; then
        fail_test "Should fail with missing arguments"
    else
        pass_test
    fi
}

# Test 3: Invalid block size (not power of 2)
test_invalid_block_size() {
    run_test "Invalid block size validation"

    echo "test" > file.txt
    zip -q test.zip file.txt

    if "$BUILD_DIR/zip-optimizer" --block-size 3000 test.zip out.zip 2>/dev/null; then
        fail_test "Should reject non-power-of-2 block size"
    else
        pass_test
    fi

    rm -f file.txt test.zip
}

# Test 4: Valid block sizes
test_valid_block_sizes() {
    run_test "Valid block sizes (512, 4096)"

    echo "test" > file.txt
    zip -q test.zip file.txt

    local success=true

    # Test 512
    if ! "$BUILD_DIR/zip-optimizer" --block-size 512 test.zip out512.zip >/dev/null 2>&1; then
        success=false
    fi

    # Test 4096
    if ! "$BUILD_DIR/zip-optimizer" --block-size 4096 test.zip out4096.zip >/dev/null 2>&1; then
        success=false
    fi

    if [ "$success" = true ]; then
        pass_test
    else
        fail_test "Valid block sizes rejected"
    fi

    rm -f file.txt test.zip out512.zip out4096.zip
}

# Test 5: Nonexistent input file
test_nonexistent_input() {
    run_test "Nonexistent input file"

    if "$BUILD_DIR/zip-optimizer" --block-size 4096 nonexistent.zip out.zip 2>/dev/null; then
        fail_test "Should fail with nonexistent input"
    else
        pass_test
    fi
}

# Test 6: Decompression of compressed files
test_decompression() {
    run_test "Decompression of compressed files"

    # Create a file that will actually compress
    for i in {1..100}; do
        echo "This is line $i with repeated text to enable compression" >> data.txt
    done

    zip -9 compressed.zip data.txt >/dev/null 2>&1

    # Verify it's compressed
    local comp_info=$(zipinfo compressed.zip | grep "data.txt")
    if ! echo "$comp_info" | grep -q "defl"; then
        fail_test "Test file not compressed"
        rm -f data.txt compressed.zip
        return
    fi

    # Optimize
    "$BUILD_DIR/zip-optimizer" --block-size 4096 compressed.zip optimized.zip >/dev/null 2>&1

    # Verify it's now stored
    local opt_info=$(zipinfo optimized.zip | grep "data.txt")
    if echo "$opt_info" | grep -q "stor"; then
        pass_test
    else
        fail_test "File not converted to stored format"
    fi

    rm -f data.txt compressed.zip optimized.zip
}

# Test 7: Data integrity after optimization
test_data_integrity() {
    run_test "Data integrity after optimization"

    # Create test file
    dd if=/dev/urandom of=random.bin bs=1K count=100 2>/dev/null
    local original_md5=$(md5sum random.bin | cut -d' ' -f1)

    # Create compressed ZIP
    zip -9 test.zip random.bin >/dev/null 2>&1

    # Optimize
    "$BUILD_DIR/zip-optimizer" --block-size 4096 test.zip optimized.zip >/dev/null 2>&1

    # Extract and verify
    unzip -q optimized.zip
    local optimized_md5=$(md5sum random.bin | cut -d' ' -f1)

    if [ "$original_md5" = "$optimized_md5" ]; then
        pass_test
    else
        fail_test "MD5 checksum mismatch after optimization"
    fi

    rm -f random.bin test.zip optimized.zip
}

# Test 8: Multiple files in ZIP
test_multiple_files() {
    run_test "Multiple files in ZIP"

    mkdir -p testdata
    for i in {1..10}; do
        echo "File $i content" > testdata/file$i.txt
    done

    zip -9 -r test.zip testdata/ >/dev/null 2>&1

    "$BUILD_DIR/zip-optimizer" --block-size 4096 test.zip optimized.zip >/dev/null 2>&1

    # Verify all files present
    local file_count=$(zipinfo optimized.zip | grep "testdata/file" | wc -l)

    if [ "$file_count" = "10" ]; then
        pass_test
    else
        fail_test "File count mismatch (expected 10, got $file_count)"
    fi

    rm -rf testdata test.zip optimized.zip
}

# Test 9: Already uncompressed files
test_already_uncompressed() {
    run_test "Already uncompressed files"

    echo "test" > file.txt
    zip -0 test.zip file.txt >/dev/null 2>&1

    local output=$("$BUILD_DIR/zip-optimizer" --block-size 4096 test.zip optimized.zip 2>&1)

    # Should show 0 files decompressed
    if echo "$output" | grep -q "Files decompressed: 0"; then
        pass_test
    else
        fail_test "Should report 0 files decompressed for already uncompressed ZIP"
    fi

    rm -f file.txt test.zip optimized.zip
}

# Test 10: Empty ZIP
test_empty_zip() {
    run_test "Empty ZIP file"

    zip -q empty.zip -@ < /dev/null || true

    if "$BUILD_DIR/zip-optimizer" --block-size 4096 empty.zip optimized.zip >/dev/null 2>&1; then
        # Should succeed with 0 files
        local output=$("$BUILD_DIR/zip-optimizer" --block-size 4096 empty.zip optimized2.zip 2>&1)
        if echo "$output" | grep -q "Files processed: 0"; then
            pass_test
        else
            fail_test "Empty ZIP not handled correctly"
        fi
    else
        fail_test "Empty ZIP caused error"
    fi

    rm -f empty.zip optimized.zip optimized2.zip
}

# Test 11: Nested directories
test_nested_directories() {
    run_test "Nested directory structures"

    mkdir -p deep/a/b/c/d
    echo "deep file" > deep/a/b/c/d/file.txt
    zip -9 -r test.zip deep/ >/dev/null 2>&1

    "$BUILD_DIR/zip-optimizer" --block-size 4096 test.zip optimized.zip >/dev/null 2>&1

    # Extract and verify structure
    unzip -q optimized.zip
    if [ -f "deep/a/b/c/d/file.txt" ]; then
        pass_test
    else
        fail_test "Nested directory structure not preserved"
    fi

    rm -rf deep test.zip optimized.zip
}

# Test 12: Output file overwrite
test_output_overwrite() {
    run_test "Output file creation/overwrite"

    echo "test" > file.txt
    zip -q test.zip file.txt

    # Create output file first
    touch output.zip

    # Should overwrite
    if "$BUILD_DIR/zip-optimizer" --block-size 4096 test.zip output.zip >/dev/null 2>&1; then
        if [ -s output.zip ]; then
            pass_test
        else
            fail_test "Output file empty after optimization"
        fi
    else
        fail_test "Failed to overwrite existing output file"
    fi

    rm -f file.txt test.zip output.zip
}

# Main execution
main() {
    echo "======================================"
    echo "zip-optimizer Test Suite"
    echo "======================================"

    trap cleanup EXIT
    setup

    # Run all tests
    test_help_output
    test_missing_arguments
    test_invalid_block_size
    test_valid_block_sizes
    test_nonexistent_input
    test_decompression
    test_data_integrity
    test_multiple_files
    test_already_uncompressed
    test_empty_zip
    test_nested_directories
    test_output_overwrite

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
