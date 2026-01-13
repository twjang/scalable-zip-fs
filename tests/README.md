# scalable-zip-fs Test Suite

Comprehensive test suite for the scalable-zip-fs project.

## Overview

This directory contains automated tests for:
- **Filesystem functionality** - FUSE mounting, reading, directory traversal
- **ZIP optimizer tool** - Decompression, validation, error handling
- **Integration** - Complete workflows combining both tools
- **Performance** - Basic performance verification

## Test Structure

```
tests/
├── test_filesystem.sh      # Filesystem mounting and operations (8 tests)
├── test_optimizer.sh        # ZIP optimizer tool tests (12 tests)
├── test_integration.sh      # End-to-end integration tests (6 tests)
├── run_all_tests.sh         # Master test runner
└── README.md                # This file
```

## Running Tests

### Prerequisites

Build the project first:
```bash
meson setup build
meson compile -C build
```

### Run All Tests

```bash
./tests/run_all_tests.sh
```

### Run Individual Test Suites

```bash
# Filesystem tests only
./tests/test_filesystem.sh

# Optimizer tests only
./tests/test_optimizer.sh

# Integration tests only
./tests/test_integration.sh
```

## Test Coverage

### Filesystem Tests (test_filesystem.sh)

1. **Mount single ZIP file** - Basic mounting functionality
2. **Read-only enforcement** - Verifies write operations are blocked
3. **Directory traversal** - Tests nested directory structures
4. **Empty files** - Handles zero-byte files correctly
5. **Large files** - 10MB file integrity verification
6. **Special characters** - Filenames with spaces, dashes, underscores
7. **Multi-archive mounting** - Multiple ZIP files to one mount point
8. **File precedence** - First ZIP wins when files conflict

### Optimizer Tests (test_optimizer.sh)

1. **Help output** - Command-line help display
2. **Missing arguments** - Error handling for missing parameters
3. **Invalid block size** - Rejects non-power-of-2 values
4. **Valid block sizes** - Accepts 512, 4096, etc.
5. **Nonexistent input** - Handles missing input files
6. **Decompression** - Converts compressed files to stored format
7. **Data integrity** - MD5 verification after optimization
8. **Multiple files** - Handles ZIPs with many files
9. **Already uncompressed** - Correctly identifies uncompressed files
10. **Empty ZIP** - Handles edge case of empty archives
11. **Nested directories** - Preserves directory structure
12. **Output overwrite** - Creates/overwrites output files

### Integration Tests (test_integration.sh)

1. **Optimize then mount** - Complete workflow with data integrity check
2. **Optimized multi-archive** - Multiple optimized ZIPs mounted together
3. **Performance comparison** - Compressed vs optimized read performance
4. **Large dataset** - 1000 files workflow
5. **Mixed compression** - Files with varying compression levels
6. **Concurrent mounts** - Same ZIP mounted at multiple points

## Test Features

- **Automatic cleanup** - Tests clean up after themselves
- **Colored output** - Green for pass, red for fail, yellow for test names
- **Detailed reporting** - Individual test results and summary statistics
- **Data integrity** - MD5 checksum verification for file contents
- **Error isolation** - Failed tests don't affect subsequent tests
- **Temporary directories** - All tests use `/tmp` to avoid clutter

## Expected Output

### Successful Run

```
================================================
scalable-zip-fs Complete Test Suite
================================================

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Running: Filesystem Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[TEST 1] Mount single ZIP file
✓ PASS

[TEST 2] Read-only filesystem enforcement
✓ PASS

...

================================================
FINAL TEST SUMMARY
================================================
Test suites run: 3
Suites passed: 3
Suites failed: 0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
       ALL TESTS PASSED SUCCESSFULLY!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Troubleshooting

### FUSE not working

If tests fail with FUSE errors:
```bash
# Check if FUSE is available
modprobe fuse
```

### Permission issues

Tests require ability to mount FUSE filesystems. Run as regular user (not root).

### Cleanup issues

If mount points aren't cleaned up:
```bash
# Manually unmount
fusermount -u /tmp/scalable-zip-fs-tests/mount
fusermount -u /tmp/scalable-zip-fs-integration/mount

# Remove test directories
rm -rf /tmp/scalable-zip-fs-*
rm -rf /tmp/scalable-zip-optimize-tests
```

## Adding New Tests

To add a new test to an existing suite:

1. Create a new test function following the naming pattern `test_<name>()`
2. Use the helper functions:
   - `run_test "<description>"` - Start a test
   - `pass_test` - Mark as passed
   - `fail_test "<message>"` - Mark as failed with reason
   - `assert_equals expected actual [message]` - Equality assertion
3. Add the test function call to the `main()` function

Example:
```bash
test_my_new_feature() {
    run_test "My new feature test"

    # Test logic here
    if [ condition ]; then
        pass_test
    else
        fail_test "Explanation of failure"
    fi
}
```

## CI/CD Integration

To integrate with CI/CD pipelines:

```bash
# Exit code 0 on success, 1 on failure
./tests/run_all_tests.sh
```

## Performance Notes

- Filesystem tests: ~30-60 seconds
- Optimizer tests: ~20-40 seconds
- Integration tests: ~60-90 seconds
- **Total runtime**: ~2-3 minutes

Large file tests may take longer depending on system I/O performance.

## Requirements

- Bash 4.0+
- FUSE 3.x
- Standard Unix utilities: `zip`, `unzip`, `md5sum`, `dd`
- Sufficient `/tmp` space (~100MB)
- Permission to mount FUSE filesystems

## License

Apache-2.0 (same as main project)
