#ifndef _UTILS_HPP
#define _UTILS_HPP

#include <list>
#include <tuple>

namespace scalable_zip_fs {


template<typename T>
class Singleton {
public:
    static T& get_instance() {
        static T instance;
        return instance;
    }

    Singleton(const Singleton&) = delete;
    Singleton& operator=(const Singleton&) = delete;
    Singleton(Singleton&&) = delete;
    Singleton& operator=(Singleton&&) = delete;

protected:
    Singleton() = default;
    virtual ~Singleton() = default;
};


class PathSplit {
public:
    PathSplit(const std::string& path);
    PathSplit(const char* pathptr, const size_t pathlen);
    
    inline const std::list<std::tuple<size_t, size_t>>& segments() {
        return segments_;
    }
    
    inline bool is_dir() const {
        return is_dir_;
    }

protected:
    std::list< std::tuple < size_t, size_t > > segments_;
    bool is_dir_;
};

size_t get_common_path_split(const char* str_a, const size_t len_a, const PathSplit& split_a);

}

#endif