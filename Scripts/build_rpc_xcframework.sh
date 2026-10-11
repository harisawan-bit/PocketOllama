#!/usr/bin/env bash
#
# Build a llama.cpp XCFramework for iOS WITH the RPC backend.
#
# WHY THIS EXISTS
# The official release XCFramework is built without RPC. Verified against the
# real b11218 asset: the ios-arm64 binary exports ggml_backend_metal and
# llama_model_load_from_file but NOT ggml_backend_rpc_init. The cause is in
# upstream's build-xcframework.sh, whose COMMON_CMAKE_ARGS passes
# -DGGML_METAL=ON and never passes -DGGML_RPC=ON.
#
# So multi-device clustering needs a locally built framework. That is what this
# script produces.
#
# REQUIRES macOS + Xcode. This cannot be built or verified on Windows, and it is
# labelled as unverified for that reason. Run it, then check the gates at the
# bottom before trusting the result.
#
# Usage:
#   ./Scripts/build_rpc_xcframework.sh [LLAMA_TAG]
# Default tag: b11218 (the version the app currently ships)

set -euo pipefail

LLAMA_TAG="${1:-b11218}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT}/Vendor/rpc-build"
OUT="${ROOT}/Vendor/llama-rpc.xcframework"
JOBS="$(sysctl -n hw.ncpu)"

echo "==> Building llama.cpp ${LLAMA_TAG} for iOS with GGML_RPC=ON"

# ---------------------------------------------------------------- prerequisites
for tool in cmake xcrun git; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "ERROR: ${tool} is required and not on PATH." >&2
        exit 1
    fi
done

# ---------------------------------------------------------------- source
# Use a shallow clone of the pinned tag rather than the release zip, because the
# release zip is the prebuilt framework we are trying to replace.
if [ ! -d "${BUILD_DIR}/llama.cpp" ]; then
    mkdir -p "${BUILD_DIR}"
    git clone --depth 1 --branch "${LLAMA_TAG}" \
        https://github.com/ggml-org/llama.cpp.git "${BUILD_DIR}/llama.cpp"
fi

SRC="${BUILD_DIR}/llama.cpp"
cd "${SRC}"

# ---------------------------------------------------------------- build (device)
#
# GGML_RPC_RDMA is forced OFF deliberately. On Apple, RDMA means
# RDMA-over-Thunderbolt via librdma.dylib, which is macOS 26.2+ and needs
# Thunderbolt 5. No iPhone has Thunderbolt. Leaving it ON would add a weak
# link against a library that does not exist on iOS.
#
# BUILD_SHARED_LIBS=ON so the result is a dynamic framework, matching what the
# app already links against.
build_one() {
    local platform="$1" sdk="$2" arch="$3" subdir="$4"

    echo "==> Configuring ${platform} (${arch})"
    rm -rf "${BUILD_DIR}/${subdir}"
    cmake -S "${SRC}" -B "${BUILD_DIR}/${subdir}" -G Xcode \
        -DCMAKE_SYSTEM_NAME="${platform}" \
        -DCMAKE_OSX_SYSROOT="${sdk}" \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 \
        -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
        -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
        \
        -DBUILD_SHARED_LIBS=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_TOOLS=OFF \
        -DLLAMA_BUILD_SERVER=OFF \
        -DLLAMA_BUILD_COMMON=OFF \
        -DLLAMA_BUILD_APP=OFF \
        -DLLAMA_CURL=OFF \
        \
        -DGGML_METAL=ON \
        -DGGML_METAL_EMBED_LIBRARY=ON \
        -DGGML_BLAS_DEFAULT=ON \
        -DGGML_RPC=ON \
        -DGGML_RPC_RDMA=OFF \
        -DGGML_NATIVE=OFF \
        -DGGML_OPENMP=OFF

    echo "==> Building ${platform}"
    cmake --build "${BUILD_DIR}/${subdir}" --config Release -j "${JOBS}" -- -quiet
}

build_one iOS iphoneos arm64 ios-device

# A simulator slice is intentionally not built. The existing app is device-only
# and the XCFramework it replaces has no simulator slice either. Add a second
# build_one call with iphonesimulator if that ever changes.

# ---------------------------------------------------------------- assemble
echo "==> Assembling XCFramework"
rm -rf "${OUT}"
mkdir -p "${BUILD_DIR}/framework/llama.framework/Headers"
mkdir -p "${BUILD_DIR}/framework/llama.framework/Modules"

# Headers the app's Swift code imports through the module map.
for hdr in llama.h ggml.h ggml-alloc.h ggml-backend.h ggml-blas.h \
            ggml-cpu.h ggml-metal.h ggml-opt.h gguf.h ggml-rpc.h; do
    if [ -f "${SRC}/include/${hdr}" ]; then
        cp "${SRC}/include/${hdr}" "${BUILD_DIR}/framework/llama.framework/Headers/"
    elif [ -f "${SRC}/ggml/include/${hdr}" ]; then
        cp "${SRC}/ggml/include/${hdr}" "${BUILD_DIR}/framework/llama.framework/Headers/"
    fi
done

# The binary CMake produced.
DYLIB="$(find "${BUILD_DIR}/ios-device" -name "libllama.dylib" -o -name "llama" -type f 2>/dev/null | head -1)"
if [ -z "${DYLIB}" ]; then
    echo "ERROR: could not locate the built library under ${BUILD_DIR}/ios-device" >&2
    echo "       Inspect that directory by hand; CMake's output layout varies by version." >&2
    exit 1
fi
cp "${DYLIB}" "${BUILD_DIR}/framework/llama.framework/llama"

# Module map. Links the frameworks the app already links, plus Metal for the
# kernels that are compiled into the library.
cat > "${BUILD_DIR}/framework/llama.framework/Modules/module.modulemap" <<'EOF'
framework module llama {
    umbrella "Headers"
    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"
    export *
}
EOF

# Info.plist. MinimumOSVersion 16.4 matches what the app already requires and
# what upstream's own script uses.
cat > "${BUILD_DIR}/framework/llama.framework/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>llama</string>
    <key>CFBundleIdentifier</key><string>org.ggml.llama.rpc</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>llama</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>16.4</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>iPhoneOS</string></array>
</dict>
</plist>
EOF

xcodebuild -create-xcframework \
    -framework "${BUILD_DIR}/framework/llama.framework" \
    -output "${OUT}"

# ---------------------------------------------------------------- gates
#
# These are the checks that matter. A build that compiles is not a build that
# works: RPC could still be silently absent, exactly as it is in the official
# release. Every symbol below must be present, and the two controls prove the
# probe itself is working.
echo "==> Verifying the built framework"
BIN="${OUT}/ios-arm64/llama.framework/llama"
FAIL=0

check_symbol() {
    local sym="$1" kind="$2"
    if nm -gU "${BIN}" 2>/dev/null | grep -q "_${sym}"; then
        echo "  ok      ${sym}"
    else
        echo "  MISSING ${sym}  (${kind})"
        FAIL=1
    fi
}

echo "  -- RPC must be present --"
check_symbol ggml_backend_rpc_init            "required"
check_symbol ggml_backend_rpc_start_server    "required"
check_symbol ggml_backend_rpc_get_device_memory "required"
check_symbol ggml_backend_rpc_add_server      "required"

echo "  -- controls, proving the probe works --"
check_symbol ggml_backend_metal               "control"
check_symbol llama_model_load_from_file       "control"

if [ "${FAIL}" -ne 0 ]; then
    echo
    echo "FAILED: the framework is missing required symbols. Do not ship it." >&2
    exit 1
fi

echo
echo "Built: ${OUT}"
echo "Next: point project.yml at this framework instead of llama.xcframework,"
echo "      then confirm the app still builds and the self-check still passes."
