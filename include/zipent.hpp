#ifndef _ZIPENT_HPP
#define _ZIPENT_HPP

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <cinttypes>
#include <filesystem>

#include "utils.hpp"


namespace scalable_zip_fs {

class FileEntry;
class DirectoryEntry;
class ZipEntryManagerImpl;


class FileEntry {
public:
    DirectoryEntry* parent_;

    inline const std::string& name() const { return *name_; }
    inline size_t size() const { return size_; }
    inline size_t zip_path_idx() const { return zip_path_idx_; }
    inline size_t offset() const { return offset_; }
    inline bool need_decompression() const { return need_decompression_; }

protected:
    const std::string* name_;

    size_t zip_path_idx_;
    size_t size_;
    size_t compressed_size_;
    size_t offset_;          // ZIP entry index
    bool need_decompression_;

    friend ZipEntryManagerImpl;
};


class DirectoryEntry {
public:
    inline const std::string& name() const { return *name_; }
    inline const std::unordered_map<std::string, std::unique_ptr<DirectoryEntry>>& dirs() const { return dirs_; }
    inline const std::unordered_map<std::string, std::unique_ptr<FileEntry>>& files() const { return files_; }

    const DirectoryEntry* find_dir(const std::string& name) const;
    const FileEntry* find_file(const std::string& name) const;

protected:
    std::unordered_map<std::string, std::unique_ptr<DirectoryEntry>> dirs_;
    std::unordered_map<std::string, std::unique_ptr<FileEntry>> files_;
    DirectoryEntry* parent_;
    const std::string* name_;

    friend ZipEntryManagerImpl;
};


class ZipEntryManagerImpl {
public:
    ZipEntryManagerImpl();

    void index_zipfile(const std::filesystem::path& path);

    const DirectoryEntry* lookup_dir(const char* path) const;
    const FileEntry* lookup_file(const char* path) const;

    inline const DirectoryEntry& root() const { return root_; }
    inline const std::string& get_zip_path(size_t idx) const { return zip_path_lst_[idx]; }

protected:
    std::vector<std::string> zip_path_lst_;
    DirectoryEntry root_;
};


typedef Singleton<ZipEntryManagerImpl> ZipEntryManager;

}

#endif
