#!/bin/bash
# Build third-party C++ static libraries for placo stack (aarch64 native by default).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSIONS="$SCRIPT_DIR/versions.yaml"
SOURCES_DIR="$SCRIPT_DIR/sources"
BUILD_DIR="$SCRIPT_DIR/build"
INSTALL_ROOT="$SCRIPT_DIR/install"
JOBS="$(nproc)"

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        *) echo "$(uname -m)" ;;
    esac
}

usage() {
    cat <<EOF
Usage: $0 [fetch|build|all] [options]

  fetch   Clone sources and checkout tags
  build   Build and install (per-library layout under install/<arch>/<name>/)
  all     fetch + build (default)

Options:
  --target <arch>     aarch64|x86_64 (default: auto-detect)
  -j <N>              Parallel jobs (default: nproc)
  --clean             Remove build/ and sources/ (not install/)
  --clean-install     Also remove install/<arch>/
  --only <name>       Build only one library (e.g. yaml-cpp)
  -h, --help          Show this help
EOF
}

ACTION="all"
ARCH="$(detect_arch)"
CLEAN=0
CLEAN_INSTALL=0
ONLY=""
PREFIX_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        fetch|build|all) ACTION="$1"; shift ;;
        --target) ARCH="$2"; shift 2 ;;
        -j) JOBS="$2"; shift 2 ;;
        --clean) CLEAN=1; shift ;;
  --clean-install) CLEAN=1; CLEAN_INSTALL=1; shift ;;
  --only) ONLY="$2"; shift 2 ;;
  -h|--help) usage; exit 0 ;;
        *) echo "Unknown: $1"; usage; exit 1 ;;
    esac
done

INSTALL_ARCH="$INSTALL_ROOT/$ARCH"
mkdir -p "$INSTALL_ARCH"

append_prefix() {
    local p="$INSTALL_ARCH/$1"
    if [ -d "$p" ]; then
        if [ -z "$PREFIX_PATH" ]; then
            PREFIX_PATH="$p"
        else
            PREFIX_PATH="$PREFIX_PATH;$p"
        fi
    fi
}

rebuild_prefix_path() {
    PREFIX_PATH=""
    local name
    for name in yaml-cpp eigen boost tinyxml2 jsoncpp console_bridge urdfdom_headers urdfdom coal eiquadprog pinocchio placo; do
        append_prefix "$name"
    done
}

lib_prefix() { echo "$INSTALL_ARCH/$1"; }

yaml_python() {
    python3 - "$@" <<'PY'
import sys, yaml
from pathlib import Path

action = sys.argv[1]
versions = yaml.safe_load(Path(sys.argv[2]).read_text())
deps = versions["dependencies"]
order = versions["build_order"]

if action == "list":
    for name in order:
        d = deps[name]
        print("|".join([
            name,
            d.get("kind", "cmake"),
            d.get("url", ""),
            str(d.get("tag", "")),
            d.get("branch", ""),
            d.get("source_dir", f"sources/{name}"),
        ]))
elif action == "get":
    name = sys.argv[3]
    d = deps[name]
    for k, v in d.items():
        print(f"{k}={v}")
PY
}

resolve_src() {
    local rel="$1"
    if [[ "$rel" == ../* ]]; then
        echo "$ROOT_DIR/${rel#../}"
    else
        echo "$SCRIPT_DIR/$rel"
    fi
}

fetch_submodule() {
    local name="$1" branch="$2" rel="$3"
    local dir subpath
    dir="$(resolve_src "$rel")"
    subpath="${rel#../}"
    echo "  [$name] submodule -> $dir (branch $branch)"
    git -C "$ROOT_DIR" submodule update --init --recursive "$subpath"
    git -C "$dir" fetch origin 2>/dev/null || true
    git -C "$dir" checkout "$branch"
    if [ "$name" = pinocchio ]; then
        git -C "$dir" submodule update --init cmake
    fi
}

fetch_one() {
    local name="$1" url="$2" tag="$3" rel="$4"
    local dir
    dir="$(resolve_src "$rel")"

    if [ -d "$dir/.git" ]; then
        echo "  [$name] exists, checkout $tag ..."
        git -C "$dir" fetch --tags origin 2>/dev/null || true
        git -C "$dir" checkout -f "$tag"
        return 0
    fi

    echo "  [$name] cloning $url @ $tag ..."
    mkdir -p "$(dirname "$dir")"
    git clone --depth 1 --branch "$tag" "$url" "$dir"
    if [ -f "$dir/.gitmodules" ]; then
        git -C "$dir" submodule update --init --depth 1 2>/dev/null || \
            git -C "$dir" submodule update --init
    fi
}

do_fetch() {
    echo "=== Fetch sources ==="
    while IFS='|' read -r name kind url tag branch rel; do
        [ -z "$name" ] && continue
        case "$kind" in
            system_boost) echo "  [$name] system package (no clone)" ;;
            submodule) fetch_submodule "$name" "${branch:-inexus}" "$rel" ;;
            *) fetch_one "$name" "$url" "$tag" "$rel" ;;
        esac
    done < <(yaml_python list "$VERSIONS")
    echo "Done."
}

ensure_apt_deps() {
    if [ -f /.dockerenv ] || [ "${SKIP_APT:-0}" = 1 ]; then
        return 0
    fi
    local pkgs=(
        build-essential cmake git pkg-config python3-yaml
        libboost-filesystem-dev libboost-system-dev libboost-serialization-dev
    )
    local missing=""
    for p in "${pkgs[@]}"; do
        dpkg -s "$p" &>/dev/null || missing="$missing $p"
    done
    if [ -n "$missing" ]; then
        echo "=== Installing apt packages:$missing ==="
        sudo apt-get update -qq
        sudo apt-get install -y $missing
    fi
}

stage_boost() {
    local dest
    dest="$(lib_prefix boost)"
    if [ -f "$dest/lib/libboost_filesystem.a" ]; then
        echo "  [boost] already staged"
        return 0
    fi
    echo "  [boost] staging system static libs ..."
    mkdir -p "$dest/lib" "$dest/include"
    local libdir="/usr/lib/$(uname -m)-linux-gnu"
    [ -d "$libdir" ] || libdir="/usr/lib"
    local comp
    for comp in filesystem system serialization; do
        cp -a "$libdir/libboost_${comp}.a" "$dest/lib/" 2>/dev/null || {
            echo "  [boost] missing libboost_${comp}.a in $libdir"
            exit 1
        }
    done
    cp -a /usr/include/boost "$dest/include/"
    # Minimal cmake hint for find_package(Boost)
    mkdir -p "$dest/lib/cmake/Boost-1.83.0"
    cat > "$dest/lib/cmake/Boost-1.83.0/BoostConfig.cmake" <<CMAKE
set(Boost_FOUND TRUE)
set(Boost_VERSION_STRING "1.83.0")
set(_boost_root "\${CMAKE_CURRENT_LIST_DIR}/../../..")
foreach(_comp filesystem system serialization)
  if(NOT TARGET Boost::\${_comp})
    add_library(Boost::\${_comp} STATIC IMPORTED)
    set_target_properties(Boost::\${_comp} PROPERTIES
      IMPORTED_LOCATION "\${_boost_root}/lib/libboost_\${_comp}.a"
      INTERFACE_INCLUDE_DIRECTORIES "\${_boost_root}/include")
  endif()
endforeach()
CMAKE
    ln -sf Boost-1.83.0 "$dest/lib/cmake/Boost"
    echo "  [boost] ok -> $dest"
}

system_cmake_extras() {
    local arch extras="" d
    arch="$(uname -m)"
    for d in "/usr/lib/${arch}-linux-gnu/cmake/assimp-"*; do
        if [ -f "$d/assimpConfig.cmake" ]; then
            extras="-Dassimp_DIR=$d"
            break
        fi
    done
    if [ -f /usr/share/octomap/octomap-config.cmake ]; then
        extras="$extras -Doctomap_DIR=/usr/share/octomap"
    fi
    echo "$extras"
}

fix_urdfdom_cmake_config() {
    local cfg
    cfg="$(lib_prefix urdfdom)/lib/urdfdom/cmake/urdfdom-config.cmake"
    [ -f "$cfg" ] || return 0
    grep -q 'find_package(console_bridge' "$cfg" && return 0
    python3 - "$cfg" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
needle = 'foreach(exp urdfdom)'
insert = (
    'find_package(console_bridge REQUIRED)\n'
    'find_package(tinyxml2 REQUIRED)\n\n'
    + needle
)
if needle in text and 'find_package(console_bridge' not in text:
    p.write_text(text.replace(needle, insert, 1))
PY
}

fix_coal_cmake_config() {
    local cfg
    cfg="$(lib_prefix coal)/lib/cmake/coal/coalConfig.cmake"
    [ -f "$cfg" ] || return 0
    grep -q 'find_dependency(assimp' "$cfg" && return 0
    python3 - "$cfg" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
needle = 'include("${CMAKE_CURRENT_LIST_DIR}/coalTargets.cmake")'
insert = (
    'find_dependency(assimp REQUIRED)\n'
    'find_dependency(octomap)\n'
    + needle
)
if needle in text:
    p.write_text(text.replace(needle, insert, 1))
PY
}

cmake_common() {
    local sys_cmake="/usr/lib/$(uname -m)-linux-gnu"
    local full_prefix="$PREFIX_PATH"
    if [ -d "$sys_cmake" ]; then
        if [ -n "$full_prefix" ]; then
            full_prefix="$full_prefix;$sys_cmake"
        else
            full_prefix="$sys_cmake"
        fi
    fi
    echo -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$1" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_PREFIX_PATH="${full_prefix}" \
        $(system_cmake_extras)
}

already_built() {
    local name="$1" marker="$2"
    [ -f "$(lib_prefix "$name")/$marker" ]
}

build_yaml_cpp() {
    already_built yaml-cpp lib/libyaml-cpp.a && return 0
    local src dest bdir
    src="$(resolve_src sources/yaml-cpp)"
    dest="$(lib_prefix yaml-cpp)"
    bdir="$BUILD_DIR/$ARCH/yaml-cpp"
    echo "  [yaml-cpp] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DYAML_CPP_BUILD_TESTS=OFF \
        -DYAML_CPP_BUILD_TOOLS=OFF \
        -DYAML_BUILD_SHARED_LIBS=OFF
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix yaml-cpp
}

build_eigen() {
    already_built eigen include/eigen3/Eigen/Core && return 0
    local src dest bdir
    src="$(resolve_src sources/eigen)"
    dest="$(lib_prefix eigen)"
    bdir="$BUILD_DIR/$ARCH/eigen"
    echo "  [eigen] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest")
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix eigen
}

build_tinyxml2() {
    already_built tinyxml2 lib/libtinyxml2.a && return 0
    local src dest bdir
    src="$(resolve_src sources/tinyxml2)"
    dest="$(lib_prefix tinyxml2)"
    bdir="$BUILD_DIR/$ARCH/tinyxml2"
    echo "  [tinyxml2] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DBUILD_SHARED_LIBS=OFF \
        -Dtinyxml2_BUILD_TESTING=OFF
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix tinyxml2
}

build_jsoncpp() {
    already_built jsoncpp lib/libjsoncpp.a && return 0
    local src dest bdir
    src="$(resolve_src sources/jsoncpp)"
    dest="$(lib_prefix jsoncpp)"
    bdir="$BUILD_DIR/$ARCH/jsoncpp"
    echo "  [jsoncpp] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DJSONCPP_WITH_TESTS=OFF \
        -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF \
        -DBUILD_OBJECT_LIBS=OFF
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix jsoncpp
}

build_console_bridge() {
    already_built console_bridge lib/libconsole_bridge.a && return 0
    local src dest bdir
    src="$(resolve_src sources/console_bridge)"
    dest="$(lib_prefix console_bridge)"
    bdir="$BUILD_DIR/$ARCH/console_bridge"
    echo "  [console_bridge] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest")
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix console_bridge
}

build_urdfdom_headers() {
    already_built urdfdom_headers include/urdfdom_headers/exportdecl.h && return 0
    local src dest bdir
    src="$(resolve_src sources/urdfdom_headers)"
    dest="$(lib_prefix urdfdom_headers)"
    bdir="$BUILD_DIR/$ARCH/urdfdom_headers"
    echo "  [urdfdom_headers] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest")
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix urdfdom_headers
}

build_urdfdom() {
    already_built urdfdom lib/liburdfdom_model.a && return 0
    local src dest bdir
    src="$(resolve_src sources/urdfdom)"
    dest="$(lib_prefix urdfdom)"
    bdir="$BUILD_DIR/$ARCH/urdfdom"
    echo "  [urdfdom] building ..."
    # 4.0.1 hardcodes SHARED in add_urdfdom_library macro
    if grep -q 'add_library(\${add_urdfdom_library_LIBNAME} SHARED' "$src/urdf_parser/CMakeLists.txt"; then
        sed -i 's/add_library(\${add_urdfdom_library_LIBNAME} SHARED/add_library(\${add_urdfdom_library_LIBNAME} STATIC/' \
            "$src/urdf_parser/CMakeLists.txt"
    fi
    rm -rf "$bdir" "$dest"
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DURDFDOM_BUILD_TESTS=OFF
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    fix_urdfdom_cmake_config
    append_prefix urdfdom
}

build_coal() {
    if already_built coal lib/libcoal.a \
        && [ -f "$(lib_prefix coal)/lib/cmake/hpp-fcl/hpp-fclConfig.cmake" ]; then
        return 0
    fi
    local src dest bdir
    src="$(resolve_src sources/coal)"
    dest="$(lib_prefix coal)"
    bdir="$BUILD_DIR/$ARCH/coal"
    echo "  [coal] building ..."
    # v3.0.2 hardcodes SHARED; patch for static .a output
    if grep -q 'SHARED' "$src/src/CMakeLists.txt"; then
        sed -i '/add_library(/,/^)/ s/SHARED/STATIC/' "$src/src/CMakeLists.txt"
    fi
    rm -rf "$bdir"
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DBUILD_PYTHON_INTERFACE=OFF \
        -DBUILD_TESTING=OFF \
        -DCOAL_BACKWARD_COMPATIBILITY_WITH_HPP_FCL=ON
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    fix_coal_cmake_config
    append_prefix coal
}

build_eiquadprog() {
    already_built eiquadprog lib/libeiquadprog.a && return 0
    local src dest bdir
    src="$(resolve_src sources/eiquadprog)"
    dest="$(lib_prefix eiquadprog)"
    bdir="$BUILD_DIR/$ARCH/eiquadprog"
    echo "  [eiquadprog] building ..."
    git -C "$src" submodule update --init cmake 2>/dev/null || true
    rm -rf "$bdir"
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DBUILD_TESTING=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_jrl-cmakemodules=TRUE
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix eiquadprog
}

build_pinocchio() {
    already_built pinocchio lib/libpinocchio_default.a && return 0
    local src dest bdir
    src="$(resolve_src ../3rd_code/pinocchio)"
    dest="$(lib_prefix pinocchio)"
    bdir="$BUILD_DIR/$ARCH/pinocchio"
    echo "  [pinocchio] building ..."
    rm -rf "$bdir"
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest") \
        -DBUILD_PYTHON_INTERFACE=OFF \
        -DBUILD_WITH_URDF_SUPPORT=ON \
        -DBUILD_WITH_HPP_FCL_SUPPORT=ON \
        -DBUILD_TESTING=OFF \
        -DINSTALL_DOCUMENTATION=OFF \
        -DBUILD_BENCHMARK=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DCOAL_DISABLE_HPP_FCL_WARNINGS=ON
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix pinocchio
}

build_placo() {
    already_built placo lib/libplaco.a && return 0
    local src dest bdir
    src="$(resolve_src ../3rd_code/placo)"
    dest="$(lib_prefix placo)"
    bdir="$BUILD_DIR/$ARCH/placo"
    echo "  [placo] building ..."
    cmake -S "$src" -B "$bdir" $(cmake_common "$dest")
    cmake --build "$bdir" -j"$JOBS"
    cmake --install "$bdir"
    append_prefix placo
}

build_one() {
    local name="$1" kind="$2"
    rebuild_prefix_path
    case "$name" in
        yaml-cpp) build_yaml_cpp ;;
        eigen) build_eigen ;;
        boost) stage_boost; append_prefix boost ;;
        tinyxml2) build_tinyxml2 ;;
        jsoncpp) build_jsoncpp ;;
        console_bridge) build_console_bridge ;;
        urdfdom_headers) build_urdfdom_headers ;;
        urdfdom) build_urdfdom ;;
        coal) build_coal ;;
        eiquadprog) build_eiquadprog ;;
        pinocchio) build_pinocchio ;;
        placo) build_placo ;;
        *) echo "Unknown library: $name"; exit 1 ;;
    esac
}

do_build() {
    ensure_apt_deps
    echo "=== Building for $ARCH -> $INSTALL_ARCH ==="
    while IFS='|' read -r name kind url tag branch rel; do
        [ -z "$name" ] && continue
        if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ]; then
            continue
        fi
        echo "--- $name ---"
        build_one "$name" "$kind"
    done < <(yaml_python list "$VERSIONS")
    echo ""
    echo "=== Done. Artifacts under $INSTALL_ARCH/ ==="
    find "$INSTALL_ARCH" -name '*.a' 2>/dev/null | sort || true
}

[ $CLEAN_INSTALL -eq 1 ] && rm -rf "$INSTALL_ARCH"
[ $CLEAN -eq 1 ] && rm -rf "$BUILD_DIR/$ARCH" "$SOURCES_DIR"

case "$ACTION" in
    fetch) do_fetch ;;
    build) do_build ;;
    all) do_fetch; do_build ;;
esac
