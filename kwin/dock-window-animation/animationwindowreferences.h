#pragma once

#include <memory>

namespace KOS
{
// VisibleRef borrows the window kept alive by DeletedRef. Explicit cleanup
// is required: reverse member destruction would otherwise delete the window
// before VisibleRef calls unrefVisible(). Assignment also releases visibility
// first because it follows declaration order.
template<typename VisibleRef, typename DeletedRef>
struct AnimationWindowReferences
{
    VisibleRef visibleRef;
    std::shared_ptr<DeletedRef> deletedRef;

    ~AnimationWindowReferences()
    {
        visibleRef = VisibleRef();
        deletedRef.reset();
    }
};
}
