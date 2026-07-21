#include "CMdCore.h"

/*
 * SwiftPM requires a source file for a Clang target. MdCore itself is linked
 * from .build/mdcore/lib/libMdCore.a by Package.swift.
 */
int cmdcore_swiftpm_anchor(void) {
    return (int)MDCORE_ABI_VERSION_MAJOR;
}
