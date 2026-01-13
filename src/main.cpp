#include <iostream>
#include <vector>
#include <filesystem>
#include <cstring>

#include "zipfs.hpp"
#include "zipent.hpp"
#include "fuse_ops.hpp"

void print_usage(const char* prog_name) {
    std::cerr << "Usage: " << prog_name << " <zip_file1> [zip_file2 ...] <mount_point> [FUSE options]\n";
    std::cerr << "\n";
    std::cerr << "Mount one or more ZIP files as a read-only filesystem.\n";
    std::cerr << "\n";
    std::cerr << "Arguments:\n";
    std::cerr << "  zip_file1 [zip_file2 ...]  One or more ZIP files to mount\n";
    std::cerr << "  mount_point                 Directory where filesystem will be mounted\n";
    std::cerr << "\n";
    std::cerr << "Common FUSE options:\n";
    std::cerr << "  -f                          Run in foreground\n";
    std::cerr << "  -d                          Enable debug output\n";
    std::cerr << "  -s                          Single-threaded mode\n";
    std::cerr << "  -o option[,option...]       Mount options\n";
    std::cerr << "\n";
    std::cerr << "Example:\n";
    std::cerr << "  " << prog_name << " archive.zip /mnt/zipfs -f\n";
    std::cerr << "  " << prog_name << " first.zip second.zip /mnt/zipfs -o ro\n";
    std::cerr << "\n";
}

int main(int argc, char **argv) {
    if (argc < 3) {
        print_usage(argv[0]);
        return 1;
    }

    // Parse arguments: find mount point (last non-option argument)
    std::vector<std::string> zip_files;
    std::string mount_point;
    std::vector<char*> fuse_args;

    // Always include program name as first FUSE arg
    fuse_args.push_back(argv[0]);

    bool parsing_files = true;
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] == '-') {
            // This is a FUSE option
            fuse_args.push_back(argv[i]);
            parsing_files = false;
        } else {
            if (parsing_files) {
                // Collect potential ZIP files
                zip_files.push_back(argv[i]);
            } else {
                std::cerr << "Error: Unexpected argument '" << argv[i] << "' after FUSE options\n";
                print_usage(argv[0]);
                return 1;
            }
        }
    }

    // Last item in zip_files should be the mount point
    if (zip_files.size() < 2) {
        std::cerr << "Error: Need at least one ZIP file and a mount point\n";
        print_usage(argv[0]);
        return 1;
    }

    mount_point = zip_files.back();
    zip_files.pop_back();

    // Validate that mount point exists and is a directory
    if (!std::filesystem::exists(mount_point)) {
        std::cerr << "Error: Mount point '" << mount_point << "' does not exist\n";
        return 1;
    }

    if (!std::filesystem::is_directory(mount_point)) {
        std::cerr << "Error: Mount point '" << mount_point << "' is not a directory\n";
        return 1;
    }

    // Validate and index all ZIP files
    std::cerr << "Indexing ZIP files...\n";
    auto& manager = scalable_zip_fs::ZipEntryManager::get_instance();

    for (const auto& zip_file : zip_files) {
        if (!std::filesystem::exists(zip_file)) {
            std::cerr << "Error: ZIP file '" << zip_file << "' does not exist\n";
            return 1;
        }

        if (!std::filesystem::is_regular_file(zip_file)) {
            std::cerr << "Error: '" << zip_file << "' is not a regular file\n";
            return 1;
        }

        std::cerr << "  Indexing: " << zip_file << "\n";
        try {
            manager.index_zipfile(zip_file);
        } catch (const std::exception& e) {
            std::cerr << "Error indexing ZIP file: " << e.what() << std::endl;
            return 1;
        }
    }

    std::cerr << "Indexing complete. Mounting filesystem at " << mount_point << "\n";

    // Add mount point to FUSE args
    fuse_args.push_back(const_cast<char*>(mount_point.c_str()));

    // Enable read-only and default permissions
    fuse_args.push_back(const_cast<char*>("-o"));
    fuse_args.push_back(const_cast<char*>("ro,default_permissions"));

    std::cerr << "\nStarting FUSE with arguments: ";
    for (const auto& arg : fuse_args) {
        std::cerr << arg << " ";
    }
    std::cerr << "\n" << std::endl;

    // Start FUSE
    int fuse_argc = fuse_args.size();
    struct fuse_operations* ops = scalable_zip_fs::get_zipfs_operations();

    int ret = fuse_main(fuse_argc, fuse_args.data(), ops, nullptr);

    return ret;
}
