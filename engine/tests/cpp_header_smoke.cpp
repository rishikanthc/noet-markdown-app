#include "mdcore.h"

#include <type_traits>

static_assert(std::is_standard_layout<MdBytes>::value, "MdBytes must be standard-layout");
static_assert(std::is_standard_layout<MdSemanticNode>::value, "MdSemanticNode must be standard-layout");
static_assert(sizeof(MdSemanticNode) == 64, "MdSemanticNode ABI mismatch");
static_assert(MDCORE_ABI_VERSION_MAJOR == 1u, "unexpected ABI major");

int main() {
    MdDocument *document = nullptr;
    MdBytes empty{nullptr, 0};
    (void)document;
    (void)empty;
    return 0;
}
