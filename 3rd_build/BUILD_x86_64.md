# x86_64 三方库编译指南

本文档说明如何在 **Linux x86_64 本机** 编译 `controller_source` 中的 placo 依赖栈，产物与已完成的 **aarch64** 构建使用同一套版本与脚本，仅安装目录不同（`install/x86_64/`）。

> **不能** 在 macOS 上直接链接这些静态库；**不能** 从 aarch64 机器交叉编译出 x86_64 产物。必须在 x86_64 Linux 上 natively 执行 `./build.sh`。

---

## 1. 你需要什么

| 项 | 要求 |
|----|------|
| 操作系统 | Linux x86_64（`uname -m` 为 `x86_64` 或 `amd64`） |
| 仓库 | 完整 `controller_source`（含 git submodule） |
| 脚本 | `3rd_build/build.sh` + `3rd_build/versions.yaml` |
| 编译方式 | 静态库（`.a`），Release，`-fPIC` |
| 产物路径 | `3rd_build/install/x86_64/<库名>/` |

**仅给 `versions.yaml` 不够**：版本清单由 yaml 定义，具体 CMake 选项、补丁、系统依赖与命令均由 `build.sh` 实现。

---

## 2. 版本锁定（与 ARM 相同）

以 placo v0.9.23 的依赖为准；权威来源：`3rd_build/versions.yaml`。

| 顺序 | 库名 | 来源 | 版本 / 分支 | 获取方式 |
|------|------|------|-------------|----------|
| 1 | yaml-cpp | jbeder/yaml-cpp | **0.8.0** | git clone tag |
| 2 | eigen | libeigen/eigen | **3.4.0** | git clone tag |
| 3 | boost | 系统包 | **1.83** 静态 `.a` | apt，拷贝到 install |
| 4 | tinyxml2 | leethomason/tinyxml2 | **10.0.0** | git clone tag |
| 5 | jsoncpp | open-source-parsers/jsoncpp | **1.9.4** | git clone tag |
| 6 | console_bridge | ros/console_bridge | **1.0.2** | git clone tag |
| 7 | urdfdom_headers | ros/urdfdom_headers | **2.0.0** | git clone tag |
| 8 | urdfdom | ros/urdfdom | **4.0.1** | git clone tag |
| 9 | coal | coal-library/coal | **v3.0.2** | git clone tag |
| 10 | eiquadprog | stack-of-tasks/eiquadprog | **v1.2.9** | git clone tag |
| 11 | pinocchio | stack-of-tasks/pinocchio | **v3.8.0** + **`inexus` 分支** | git submodule |
| 12 | placo | Rhoban/placo | **v0.9.23** + **`inexus` 分支** | git submodule |

**编译顺序**（必须按此顺序，后者依赖前者）：

```
yaml-cpp → eigen → boost → tinyxml2 → jsoncpp → console_bridge
→ urdfdom_headers → urdfdom → coal → eiquadprog → pinocchio → placo
```

pinocchio / placo 使用仓库内 **inexus 补丁分支**，不是上游 tag 裸源码。

---

## 3. 系统依赖（apt）

在 x86_64 Linux 上安装：

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake git pkg-config python3-yaml \
  libboost-filesystem-dev libboost-system-dev libboost-serialization-dev \
  libassimp-dev liboctomap-dev
```

说明：

- **boost**：不编源码，从 `/usr/lib/x86_64-linux-gnu/libboost_*.a` 拷贝到 `install/x86_64/boost/`。
- **assimp / octomap**：仅 coal、pinocchio **构建期** CMake 需要；最终链接的是本仓库编出的静态库。

`build.sh` 在非 Docker 环境下会自动尝试安装前几项 apt 包；**assimp / octomap 需手动安装**（见上）。

---

## 4. 获取源码

```bash
git clone <controller_source 仓库 URL>
cd controller_source

# 初始化 pinocchio、placo submodule（inexus 分支）
git submodule update --init --recursive 3rd_code/placo 3rd_code/pinocchio
git -C 3rd_code/placo checkout inexus
git -C 3rd_code/pinocchio checkout inexus
```

传递依赖（yaml-cpp、eigen 等）无需手动 clone，`build.sh fetch` 会按 `versions.yaml` 拉到 `3rd_build/sources/`。

---

## 5. 编译 x86_64

```bash
cd controller_source/3rd_build

# 推荐：显式指定架构（即使已在 x86 机器上）
./build.sh all --target x86_64

# 若在 x86_64 本机且省略 --target，脚本会自动检测为 x86_64
./build.sh all

# 内存较小时降低并行度
./build.sh all --target x86_64 -j 2
```

分步执行：

```bash
./build.sh fetch --target x86_64    # 仅拉源码
./build.sh build --target x86_64    # 仅编译安装
```

只编某一库（例如 yaml-cpp）：

```bash
./build.sh build --target x86_64 --only yaml-cpp
```

清理后重编（保留已有 install）：

```bash
./build.sh build --target x86_64 --clean
```

清空该架构全部产物：

```bash
./build.sh build --target x86_64 --clean-install
```

---

## 6. 产物布局

成功后在：

```
3rd_build/install/x86_64/
├── yaml-cpp/   lib/libyaml-cpp.a          include/
├── eigen/      include/eigen3/
├── boost/      lib/libboost_*.a           include/boost/
├── tinyxml2/   lib/libtinyxml2.a          include/
├── jsoncpp/    lib/libjsoncpp.a           include/
├── console_bridge/ ...
├── urdfdom_headers/ ...
├── urdfdom/    lib/liburdfdom_*.a         ...
├── coal/       lib/libcoal.a              lib/cmake/hpp-fcl/ ...
├── eiquadprog/ lib/libeiquadprog.a        ...
├── pinocchio/  lib/libpinocchio_*.a       include/
└── placo/      lib/libplaco.a             include/
```

拷走使用：

```bash
cp -a 3rd_build/install/x86_64/ /path/to/3rd/x86_64/
```

---

## 7. 验证链接

```bash
cd 3rd_build/test_link
cmake -S . -B build -DTHIRD_ROOT="../install/x86_64"
cmake --build build
./build/test_link
```

期望输出（数值可能因环境略有差异）：

```
pinocchio nq=0 placo wrap_angle(4.0)=-2.28319
```

---

## 8. 下游 CMake 集成

```cmake
set(THIRD_ROOT /path/to/3rd/x86_64)
list(APPEND CMAKE_PREFIX_PATH
    ${THIRD_ROOT}/yaml-cpp
    ${THIRD_ROOT}/eigen
    ${THIRD_ROOT}/boost
    ${THIRD_ROOT}/tinyxml2
    ${THIRD_ROOT}/jsoncpp
    ${THIRD_ROOT}/console_bridge
    ${THIRD_ROOT}/urdfdom_headers
    ${THIRD_ROOT}/urdfdom
    ${THIRD_ROOT}/coal
    ${THIRD_ROOT}/eiquadprog
    ${THIRD_ROOT}/pinocchio
    ${THIRD_ROOT}/placo
)
add_compile_definitions(COAL_DISABLE_HPP_FCL_WARNINGS)

find_package(pinocchio REQUIRED)
find_package(eiquadprog REQUIRED)

target_include_directories(myapp PRIVATE ${THIRD_ROOT}/placo/include)
target_link_libraries(myapp PRIVATE
    ${THIRD_ROOT}/placo/lib/libplaco.a
    pinocchio::pinocchio
    eiquadprog::eiquadprog
)
```

链接进 `.so` 时，各静态库均已带 `-fPIC`。

---

## 9. 与 aarch64 构建的关系

| 项 | aarch64 | x86_64 |
|----|---------|--------|
| 版本 / 顺序 | 相同（`versions.yaml`） | 相同 |
| 脚本 | `./build.sh` | `./build.sh --target x86_64` |
| 源码目录 | `sources/`、`3rd_code/` 共用 | 共用 |
| 中间目录 | `build/aarch64/` | `build/x86_64/` |
| 产物 | `install/aarch64/` | `install/x86_64/` |
| boost | 该架构系统静态库 | 该架构系统静态库 |

同一台机器若两种架构都要：分别在 **对应架构的 Linux 环境** 各跑一遍；`sources/` 可复用，`install/<arch>/` 互不覆盖。

---

## 10. 常见问题

**Q: 只有 `versions.yaml`，能编吗？**  
A: 不能。必须还有 `build.sh`、submodule 源码及 Linux x86_64 环境。

**Q: 在 Mac 上跑 `./build.sh` 可以吗？**  
A: 可以在 Mac 上 **拉源码**（fetch），但 **编译与链接** 请在 Linux x86_64 完成；Mac 无法使用产出的 Linux `.a`。

**Q: `libboost_*.a` 找不到？**  
A: 安装 `libboost-filesystem-dev` 等包；Ubuntu 上路径一般为 `/usr/lib/x86_64-linux-gnu/`。

**Q: coal / pinocchio CMake 报 assimp / octomap？**  
A: `sudo apt-get install libassimp-dev liboctomap-dev`。

**Q: submodule 不是 inexus？**  
A: `git -C 3rd_code/pinocchio checkout inexus` 与 placo 同理；父仓 submodule SHA 为准以保证可复现。

---

## 11. 最小命令清单（复制即用）

```bash
# 环境：Linux x86_64
sudo apt-get update && sudo apt-get install -y \
  build-essential cmake git pkg-config python3-yaml \
  libboost-filesystem-dev libboost-system-dev libboost-serialization-dev \
  libassimp-dev liboctomap-dev

git clone <repo> && cd controller_source
git submodule update --init --recursive 3rd_code/placo 3rd_code/pinocchio

cd 3rd_build
./build.sh all --target x86_64

# 验证
cd test_link && cmake -S . -B build -DTHIRD_ROOT="../install/x86_64" \
  && cmake --build build && ./build/test_link
```
