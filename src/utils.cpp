#include <cassert>
#include <list>
#include <string>
#include <tuple>

#include "utils.hpp"

namespace scalable_zip_fs {

PathSplit::PathSplit(const char* pathptr, const size_t pathlen) {
    size_t i = 0;
    size_t seg_start = 0;
    size_t seg_end = 0;

    bool seg_found = false;
    bool last_was_dots = false;

    is_dir_ = false;
    if (pathlen > 0) {
        assert(pathptr != nullptr);
    }
    if (pathlen > 0)
        is_dir_ = pathptr[pathlen-1] == '/';
    
    while (i <= pathlen) {
        seg_found = false;
        if (i == pathlen || pathptr[i] == '/') {
            seg_end = i;
            seg_found = true;
        }
        
        if (seg_found) {
            last_was_dots = false;
            size_t seg_len = seg_end - seg_start;
            if (seg_len) {
                if (seg_len == 1 && pathptr[seg_start] == '.') {
                    last_was_dots = true;
                } else if (seg_len == 2 && pathptr[seg_start] == '.' && pathptr[seg_start + 1] == '.') {
                    if (!segments_.empty()) {
                        segments_.pop_back();
                    }
                    last_was_dots = true;
                } else {
                    segments_.push_back(std::make_tuple(seg_start, seg_end));
                }
            }
            seg_start = i + 1;
        }
        i++;
    }
    
    is_dir_ |= last_was_dots;
}

PathSplit::PathSplit(const std::string& path): PathSplit::PathSplit(path.c_str(), path.length()) { }


} // namespace scalable_zip_fs
