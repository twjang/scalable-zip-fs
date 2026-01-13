#include <cassert>
#include <tuple>

#include "utils.hpp"

using scalable_zip_fs::PathSplit;

static void expect_single_segment(PathSplit& split, size_t start, size_t end) {
    auto& segments = split.segments();
    assert(segments.size() == 1);
    const auto& first = segments.front();
    assert(std::get<0>(first) == start);
    assert(std::get<1>(first) == end);
}

int main() {
    {
        PathSplit split("");
        assert(!split.is_dir());
        assert(split.segments().empty());
    }
    {
        PathSplit split("..");
        assert(split.is_dir());
        assert(split.segments().empty());
    }
    {
        PathSplit split("a/..");
        assert(split.is_dir());
        assert(split.segments().empty());
    }
    {
        PathSplit split("../b");
        assert(!split.is_dir());
        expect_single_segment(split, 3, 4);
    }
    return 0;
}
