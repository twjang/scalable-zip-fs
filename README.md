# scalable-zip-fs

A high-performance, FUSE-based filesystem implementation for uncompressed ZIP files, designed for HPC scenarios such as large-scale training workloads.

## Overview

scalable-zip-fs provides a read-only filesystem that efficiently mounts ZIP archives with millions of files. It leverages modern kernel features and efficient in-memory indexing to deliver extreme I/O performance for data-intensive applications.

## Key Features

* **io_uring support** - Utilizes the high-performance io_uring interface for the FUSE daemon
* **Multi-threaded architecture** - Supports concurrent operations for extreme I/O performance
* **Read-only access** - Once mounted, filesystem contents are immutable
* **Multi-archive mounting** - Mount multiple ZIP files to the same mount point
  * When files conflict across archives, the first archive in the argument list takes precedence
* **Efficient in-memory indexing** - Handles millions of files (2M+) with minimal memory overhead and optimized data structures
* **ZIP optimization tool** - Convert standard ZIP files to performance-optimized archives:
  * Ensures all files are decompressed (stored format)
  * Aligns file contents to configurable block boundaries (e.g., 512, 4096 bytes)

## Requirements

* C++ compiler with C++17 support or later
* FUSE 3.x library
* Linux kernel with io_uring support (5.1+)
* Meson build system

## Building

```bash
meson setup build
meson compile -C build
```

## Usage

### Mounting a ZIP file

```bash
./build/scalable-zip-fs /path/to/archive.zip /mount/point
```

### Mounting multiple ZIP files

```bash
./build/scalable-zip-fs /path/to/first.zip /path/to/second.zip /mount/point
```

### Optimizing a ZIP file

```bash
./build/scalable-zip-optimize --block-size 4096 input.zip output.zip
```

## Performance Considerations

* For optimal performance, use the ZIP optimization tool to ensure files are uncompressed and aligned
* Block alignment significantly improves throughput when accessing files
* Multi-threading scales with available CPU cores

## License

Apache-2.0

## Contributing

Currently I don't accept contributions
