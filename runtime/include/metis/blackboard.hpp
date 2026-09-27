// The blackboard — BT.cpp's shared-memory seam, with its v4 subtree
// semantics: every scope is ISOLATED by default; a child scope sees a
// parent key only through an EXPLICIT remap (child key -> parent
// key). No implicit global namespace — data flow between scopes is
// declared, hence auditable, matching the catalog doctrine (ports
// declare what they read).
//
// Role in metis: bindings capture a Blackboard at registration (the
// registerNodeType pattern) and read world/geometry data from it at
// evaluation; the DECODED typed message -> blackboard -> bindings ->
// measure. The blackboard is deliberately not visible to the kernel:
// the measure reads state through counts, bindings read the world
// through here.
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <variant>

namespace metis {

using BBValue = std::variant<bool, int64_t, double, std::string,
                             const void*>;

class Blackboard {
  public:
    using Ptr = std::shared_ptr<Blackboard>;

    static Ptr create() { return Ptr(new Blackboard(nullptr, {})); }

    // A child scope: isolated except for the declared remaps
    // (child key -> parent key), read/write through the alias.
    Ptr child(std::unordered_map<std::string, std::string> remap) {
        return Ptr(new Blackboard(this, std::move(remap)));
    }

    template <typename T>
    void set(const std::string& key, T value) {
        auto it = remap_.find(key);
        if (it != remap_.end() && parent_) {
            parent_->set<T>(it->second, std::move(value));
            return;
        }
        store_[key] = BBValue(std::move(value));
    }

    void set(const std::string& key, const char* value) {
        set<std::string>(key, std::string(value));
    }

    template <typename T>
    const T* get(const std::string& key) const {
        auto it = remap_.find(key);
        if (it != remap_.end() && parent_)
            return parent_->get<T>(it->second);
        auto s = store_.find(key);
        if (s == store_.end()) return nullptr;
        return std::get_if<T>(&s->second);
    }

    template <typename T>
    T get_or(const std::string& key, T fallback) const {
        const T* v = get<T>(key);
        return v ? *v : fallback;
    }

    bool has(const std::string& key) const {
        auto it = remap_.find(key);
        if (it != remap_.end() && parent_)
            return parent_->has(it->second);
        return store_.count(key) != 0;
    }

  private:
    Blackboard(Blackboard* parent,
               std::unordered_map<std::string, std::string> remap)
        : parent_(parent), remap_(std::move(remap)) {}

    Blackboard* parent_;
    std::unordered_map<std::string, std::string> remap_;
    std::unordered_map<std::string, BBValue> store_;
};

}  // namespace metis
