#include "Threading.hpp"
#include <stdexcept>

namespace cu59 {

void requireThreadSupport(Threading t) {
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
    if (t == Threading::Threads) throw std::logic_error("this build has no threads: use Threading::Cooperative");
#else
    (void)t;
#endif
}

} // namespace cu59
