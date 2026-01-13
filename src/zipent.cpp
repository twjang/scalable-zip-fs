#include <zip.h>
#include <iostream>
#include <stdexcept>
#include <cstring>
#include "zipent.hpp"

namespace scalable_zip_fs {

ZipEntryManagerImpl::ZipEntryManagerImpl() {
    root_.parent_ = nullptr;
    root_.name_ = &zip_path_lst_.emplace_back("");
}

void ZipEntryManagerImpl::index_zipfile(const std::filesystem::path& path) {
    // Convert to absolute path to handle relative paths
    std::filesystem::path abs_path = std::filesystem::absolute(path);

    int err = 0;
    zip_t* za = zip_open(abs_path.c_str(), ZIP_RDONLY, &err);

    if (za == nullptr) {
        zip_error_t error;
        zip_error_init_with_code(&error, err);
        std::string error_msg = "Failed to open ZIP file: " + abs_path.string() + " - " + zip_error_strerror(&error);
        zip_error_fini(&error);
        throw std::runtime_error(error_msg);
    }

    // Store the absolute ZIP file path
    size_t zip_idx = zip_path_lst_.size();
    zip_path_lst_.push_back(abs_path.string());

    zip_int64_t num_entries = zip_get_num_entries(za, 0);

    size_t indexed_files = 0;
    size_t skipped_dirs = 0;
    size_t skipped_duplicates = 0;
    size_t compressed_files = 0;

    for (zip_int64_t i = 0; i < num_entries; i++) {
        struct zip_stat st;
        zip_stat_init(&st);

        if (zip_stat_index(za, i, 0, &st) != 0) {
            std::cerr << "Warning: Failed to stat entry " << i << " in " << path << std::endl;
            continue;
        }

        if (!(st.valid & ZIP_STAT_NAME) || !(st.valid & ZIP_STAT_SIZE)) {
            std::cerr << "Warning: Entry " << i << " missing required metadata" << std::endl;
            continue;
        }

        const char* name = st.name;
        size_t name_len = std::strlen(name);

        // Skip directories (entries ending with '/')
        if (name_len > 0 && name[name_len - 1] == '/') {
            skipped_dirs++;
            continue;
        }

        // Parse the path
        PathSplit path_split(name, name_len);

        if (path_split.is_dir()) {
            skipped_dirs++;
            continue; // Skip directory entries
        }

        // Navigate/create directory structure
        DirectoryEntry* current_dir = &root_;
        const auto& segments = path_split.segments();

        auto it = segments.begin();
        auto end = segments.end();

        // All segments except the last are directories
        if (it != end) {
            auto last = std::prev(end);

            for (; it != last; ++it) {
                size_t start = std::get<0>(*it);
                size_t finish = std::get<1>(*it);
                std::string dir_name(name + start, finish - start);

                // Check if directory already exists
                auto dir_it = current_dir->dirs_.find(dir_name);
                if (dir_it == current_dir->dirs_.end()) {
                    // Create new directory
                    DirectoryEntry new_dir;
                    new_dir.parent_ = current_dir;
                    auto result = current_dir->dirs_.emplace(dir_name, std::move(new_dir));
                    current_dir = &result.first->second;
                    // Store pointer to the key in the map for name_
                    current_dir->name_ = &result.first->first;
                } else {
                    current_dir = &dir_it->second;
                }
            }

            // Last segment is the file name
            size_t start = std::get<0>(*last);
            size_t finish = std::get<1>(*last);
            std::string file_name(name + start, finish - start);

            // Check if file already exists (from a previous ZIP file)
            if (current_dir->files_.find(file_name) != current_dir->files_.end()) {
                // File already exists from earlier ZIP file, skip (first takes precedence)
                skipped_duplicates++;
                continue;
            }

            // Create file entry
            FileEntry file_entry;
            file_entry.parent_ = current_dir;
            file_entry.zip_path_idx_ = zip_idx;
            file_entry.size_ = st.size;
            file_entry.compressed_size_ = st.comp_size;

            // Get compression method
            zip_uint16_t comp_method = 0;
            if (st.valid & ZIP_STAT_COMP_METHOD) {
                comp_method = st.comp_method;
            }
            file_entry.need_decompression_ = (comp_method != ZIP_CM_STORE);

            // Track compressed files
            if (file_entry.need_decompression_) {
                compressed_files++;
            }

            // Get local header offset
            if (st.valid & ZIP_STAT_COMP_SIZE) {
                // We need to calculate the actual data offset
                // For now, store the index; we'll resolve offset on read
                file_entry.offset_ = i;
            } else {
                file_entry.offset_ = 0;
            }

            // Insert file entry
            auto result = current_dir->files_.emplace(file_name, std::move(file_entry));
            // Store pointer to the key in the map for name_
            result.first->second.name_ = &result.first->first;
            indexed_files++;
        }
    }

    zip_close(za);

    // Print indexing statistics
    std::cerr << "    Files indexed: " << indexed_files;
    if (skipped_duplicates > 0) {
        std::cerr << ", Duplicates skipped: " << skipped_duplicates;
    }
    if (compressed_files > 0) {
        std::cerr << ", Compressed: " << compressed_files
                  << " (WARNING: Performance will be degraded. Use uncompressed ZIPs!)";
    }
    std::cerr << std::endl;
}

const DirectoryEntry* DirectoryEntry::find_dir(const std::string& name) const {
    auto it = dirs_.find(name);
    if (it != dirs_.end()) {
        return &it->second;
    }
    return nullptr;
}

const FileEntry* DirectoryEntry::find_file(const std::string& name) const {
    auto it = files_.find(name);
    if (it != files_.end()) {
        return &it->second;
    }
    return nullptr;
}

const DirectoryEntry* ZipEntryManagerImpl::lookup_dir(const char* path) const {
    if (path[0] == '\0' || (path[0] == '/' && path[1] == '\0')) {
        return &root_;
    }

    PathSplit path_split(path, std::strlen(path));
    const auto& segments = path_split.segments();

    const DirectoryEntry* current_dir = &root_;

    for (const auto& seg : segments) {
        size_t start = std::get<0>(seg);
        size_t finish = std::get<1>(seg);
        std::string name(path + start, finish - start);

        current_dir = current_dir->find_dir(name);
        if (!current_dir) {
            return nullptr;
        }
    }

    return current_dir;
}

const FileEntry* ZipEntryManagerImpl::lookup_file(const char* path) const {
    if (path[0] == '\0') {
        return nullptr;
    }

    PathSplit path_split(path, std::strlen(path));

    if (path_split.is_dir()) {
        return nullptr;
    }

    const auto& segments = path_split.segments();

    if (segments.empty()) {
        return nullptr;
    }

    const DirectoryEntry* current_dir = &root_;
    auto it = segments.begin();
    auto end = segments.end();
    auto last = std::prev(end);

    // Navigate to parent directory
    for (; it != last; ++it) {
        size_t start = std::get<0>(*it);
        size_t finish = std::get<1>(*it);
        std::string name(path + start, finish - start);

        current_dir = current_dir->find_dir(name);
        if (!current_dir) {
            return nullptr;
        }
    }

    // Look up the file in the final directory
    size_t start = std::get<0>(*last);
    size_t finish = std::get<1>(*last);
    std::string file_name(path + start, finish - start);

    return current_dir->find_file(file_name);
}

} // namespace scalable_zip_fs
