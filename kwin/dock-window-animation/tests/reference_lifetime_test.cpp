#include "../animationwindowreferences.h"

#include <cstdlib>
#include <iostream>
#include <unordered_map>

struct Lifetime {
    bool alive = true;
    int invalidVisibleReleases = 0;
    int visibleReleases = 0;
    int deletedReleases = 0;
};

struct VisibleRef {
    Lifetime *state = nullptr;
    VisibleRef() = default;
    explicit VisibleRef(Lifetime &state) : state(&state) {}
    VisibleRef(const VisibleRef &) = default;
    VisibleRef &operator=(const VisibleRef &other) {
        if (this != &other) { release(); state = other.state; }
        return *this;
    }
    ~VisibleRef() { release(); }
    void release() {
        if (state) {
            if (!state->alive) ++state->invalidVisibleReleases;
            ++state->visibleReleases;
            state = nullptr;
        }
    }
};

struct DeletedRef {
    Lifetime &state;
    explicit DeletedRef(Lifetime &state) : state(state) {}
    ~DeletedRef() { state.alive = false; ++state.deletedReleases; }
};

using References = KOS::AnimationWindowReferences<VisibleRef, DeletedRef>;

static void require(bool condition, const char *message) {
    if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}

static References references(Lifetime &state) {
    References result;
    result.deletedRef = std::make_shared<DeletedRef>(state);
    result.visibleRef = VisibleRef(state);
    return result;
}

int main() {
    Lifetime scope;
    { auto refs = references(scope); }
    require(scope.invalidVisibleReleases == 0 && scope.deletedReleases == 1,
            "scope destroyed the window before releasing visibility");
    Lifetime assignment;
    { auto refs = references(assignment); refs = References(); }
    require(assignment.invalidVisibleReleases == 0 && assignment.deletedReleases == 1,
            "assignment destroyed the window before releasing visibility");
    Lifetime table;
    {
        std::unordered_map<int, References> animations;
        animations.emplace(1, references(table));
        auto finished = animations.extract(1);
        animations.clear();
        require(table.alive, "detached state lost the window reference");
    }
    require(table.invalidVisibleReleases == 0 && table.deletedReleases == 1,
            "detached state destroyed the window before releasing visibility");
    std::cout << "PASS animation reference destruction, assignment and detached state\n";
}
