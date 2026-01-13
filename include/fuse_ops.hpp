#ifndef _FUSE_OPS_HPP
#define _FUSE_OPS_HPP

#define FUSE_USE_VERSION 31

#include <fuse3/fuse.h>

namespace scalable_zip_fs {

// FUSE operation callbacks
void* zipfs_init(struct fuse_conn_info *conn, struct fuse_config *cfg);
void zipfs_destroy(void *private_data);
int zipfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi);
int zipfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                  off_t offset, struct fuse_file_info *fi,
                  enum fuse_readdir_flags flags);
int zipfs_open(const char *path, struct fuse_file_info *fi);
int zipfs_read(const char *path, char *buf, size_t size, off_t offset,
               struct fuse_file_info *fi);
int zipfs_release(const char *path, struct fuse_file_info *fi);

// Get FUSE operations structure
struct fuse_operations* get_zipfs_operations();

} // namespace scalable_zip_fs

#endif
