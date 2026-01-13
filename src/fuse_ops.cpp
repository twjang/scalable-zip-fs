#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <zip.h>
#include <iostream>

#include "fuse_ops.hpp"
#include "zipent.hpp"

namespace scalable_zip_fs {

void* zipfs_init(struct fuse_conn_info *conn, struct fuse_config *cfg) {
    // Enable io_uring if available
    if (conn->capable & FUSE_CAP_ASYNC_READ) {
        conn->want |= FUSE_CAP_ASYNC_READ;
        std::cerr << "Enabled FUSE_CAP_ASYNC_READ" << std::endl;
    }

    if (conn->capable & FUSE_CAP_PARALLEL_DIROPS) {
        conn->want |= FUSE_CAP_PARALLEL_DIROPS;
        std::cerr << "Enabled FUSE_CAP_PARALLEL_DIROPS" << std::endl;
    }

    cfg->kernel_cache = 1;
    cfg->use_ino = 1;
    cfg->nullpath_ok = 0;

    // Enable multi-threading
    cfg->direct_io = 0;

    std::cerr << "FUSE filesystem initialized with optimizations" << std::endl;
    return nullptr;
}

void zipfs_destroy(void *private_data) {
    (void) private_data;
    std::cerr << "FUSE filesystem shutting down" << std::endl;
}

int zipfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
    (void) fi;

    memset(stbuf, 0, sizeof(struct stat));

    auto& manager = ZipEntryManager::get_instance();

    // Check if it's a directory
    const DirectoryEntry* dir = manager.lookup_dir(path);
    if (dir) {
        stbuf->st_mode = S_IFDIR | 0555;
        stbuf->st_nlink = 2;
        stbuf->st_size = 4096;
        return 0;
    }

    // Check if it's a file
    const FileEntry* file = manager.lookup_file(path);
    if (file) {
        stbuf->st_mode = S_IFREG | 0444;
        stbuf->st_nlink = 1;
        stbuf->st_size = file->size();
        return 0;
    }

    return -ENOENT;
}

int zipfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                  off_t offset, struct fuse_file_info *fi,
                  enum fuse_readdir_flags flags) {
    (void) offset;
    (void) fi;
    (void) flags;

    auto& manager = ZipEntryManager::get_instance();

    const DirectoryEntry* dir = manager.lookup_dir(path);
    if (!dir) {
        return -ENOENT;
    }

    filler(buf, ".", nullptr, 0, (fuse_fill_dir_flags)0);
    filler(buf, "..", nullptr, 0, (fuse_fill_dir_flags)0);

    // Add subdirectories
    for (const auto& entry : dir->dirs()) {
        filler(buf, entry.first.c_str(), nullptr, 0, (fuse_fill_dir_flags)0);
    }

    // Add files
    for (const auto& entry : dir->files()) {
        filler(buf, entry.first.c_str(), nullptr, 0, (fuse_fill_dir_flags)0);
    }

    return 0;
}

int zipfs_open(const char *path, struct fuse_file_info *fi) {
    auto& manager = ZipEntryManager::get_instance();

    const FileEntry* file = manager.lookup_file(path);
    if (!file) {
        return -ENOENT;
    }

    // Only allow read-only access
    if ((fi->flags & O_ACCMODE) != O_RDONLY) {
        return -EACCES;
    }

    return 0;
}

int zipfs_read(const char *path, char *buf, size_t size, off_t offset,
               struct fuse_file_info *fi) {
    (void) fi;

    auto& manager = ZipEntryManager::get_instance();

    const FileEntry* file = manager.lookup_file(path);
    if (!file) {
        return -ENOENT;
    }

    // Check bounds
    if (offset >= (off_t)file->size()) {
        return 0;
    }

    // Adjust size if reading past end of file
    if (offset + size > file->size()) {
        size = file->size() - offset;
    }

    // Open the ZIP file (will be cached by OS for uncompressed ZIPs)
    const std::string& zip_path = manager.get_zip_path(file->zip_path_idx());
    int err = 0;
    zip_t* za = zip_open(zip_path.c_str(), ZIP_RDONLY, &err);

    if (za == nullptr) {
        std::cerr << "Failed to open ZIP file: " << zip_path << std::endl;
        return -EIO;
    }

    // Open the file within the ZIP
    zip_file_t* zf = zip_fopen_index(za, file->offset(), 0);
    if (zf == nullptr) {
        std::cerr << "Failed to open file in ZIP at index " << file->offset() << std::endl;
        zip_close(za);
        return -EIO;
    }

    // Seek to the offset if needed
    if (offset > 0) {
        // We need to read and discard bytes up to the offset
        char discard_buf[4096];
        off_t remaining = offset;
        while (remaining > 0) {
            size_t to_read = (remaining > 4096) ? 4096 : remaining;
            zip_int64_t result = zip_fread(zf, discard_buf, to_read);
            if (result < 0) {
                zip_fclose(zf);
                zip_close(za);
                return -EIO;
            }
            remaining -= result;
            if (result == 0) {
                break;
            }
        }
    }

    // Read the actual data
    zip_int64_t bytes_read = zip_fread(zf, buf, size);

    zip_fclose(zf);
    zip_close(za);

    if (bytes_read < 0) {
        return -EIO;
    }

    return bytes_read;
}

int zipfs_release(const char *path, struct fuse_file_info *fi) {
    (void) path;
    (void) fi;
    return 0;
}

struct fuse_operations* get_zipfs_operations() {
    static struct fuse_operations ops = {};

    ops.init = zipfs_init;
    ops.destroy = zipfs_destroy;
    ops.getattr = zipfs_getattr;
    ops.readdir = zipfs_readdir;
    ops.open = zipfs_open;
    ops.read = zipfs_read;
    ops.release = zipfs_release;

    return &ops;
}

} // namespace scalable_zip_fs
