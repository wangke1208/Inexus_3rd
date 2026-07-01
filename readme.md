# controller_source 三方库

本仓库通过 **git submodule** 管理需维护的主库源码，通过 **`3rd_build/`** 脚本拉取传递依赖、编译并安装纯 C++ 静态库产物。

## 目录结构

```
controller_source/
├── .gitmodules              # placo、pinocchio submodule（分支 inexus）
├── 3rd_code/                # 源码 submodule
│   ├── placo/               # v0.9.23 基准 + inexus patch（静态 libplaco）
│   └── pinocchio/           # v3.8.0 基准 + inexus patch（静态库）
├── 3rd_build/
│   ├── versions.yaml        # 传递依赖 url + tag
│   ├── build.sh             # fetch / build / all
│   ├── sources/             # 按 tag clone 的传递依赖（可删）
│   ├── build/               # CMake 中间目录（可删）
│   ├── install/<arch>/      # 按库名分目录的最终产物
│   └── test_link/           # 最小 C++ 链接验证
└── readme.md
```

## Submodule 与 inexus 分支

| 路径 | 上游 | 基准 tag | 工作分支 |
|------|------|----------|----------|
| `3rd_code/placo` | Rhoban/placo | v0.9.23 | `inexus` |
| `3rd_code/pinocchio` | stack-of-tasks/pinocchio | v3.8.0 | `inexus` |

初始化：

```bash
git submodule update --init --recursive 3rd_code/placo 3rd_code/pinocchio
git -C 3rd_code/placo checkout inexus
git -C 3rd_code/pinocchio checkout inexus
```

父仓记录的是 submodule **commit SHA**；日常以 SHA 保证可复现，`branch = inexus` 便于 `git submodule update --remote`。

## 构建

脚本按 **`uname -m` 自动选择架构**，产物分别落在 `install/aarch64/` 或 `install/x86_64/`。也可显式指定：`./3rd_build/build.sh all --target x86_64`。

| 架构 | 环境 | 详细说明 |
|------|------|----------|
| aarch64 | Linux ARM64 本机 / 容器 | 下文命令 |
| x86_64 | Linux x86_64 本机 | **[3rd_build/BUILD_x86_64.md](3rd_build/BUILD_x86_64.md)**（版本表、apt 依赖、验证步骤） |

在 aarch64 本机（当前容器）：

```bash
./3rd_build/build.sh all              # fetch + build，自动检测 arch
./3rd_build/build.sh all -j 2         # 内存较小时降低并行度
./3rd_build/build.sh fetch            # 仅拉源码
./3rd_build/build.sh build --clean    # 清 sources/、build/ 后重编（保留 install/）
```

x86_64 示例：

```bash
./3rd_build/build.sh all --target x86_64
```

产物布局示例（每个库独立 `lib/` + `include/`）：

```
3rd_build/install/aarch64/
├── yaml-cpp/lib/libyaml-cpp.a  yaml-cpp/include/
├── eigen/include/eigen3/
├── boost/lib/  boost/include/
├── pinocchio/lib/libpinocchio_*.a  pinocchio/include/
├── placo/lib/libplaco.a            placo/include/
└── ...
```

**说明：**

- 全程 **纯 C++ 静态库**，不编译 Python 绑定。
- **boost** 暂用系统 1.83 静态 `.a` 拷贝到 `install/.../boost/`（非源码 1.89）。
- **coal** 启用 `COAL_BACKWARD_COMPATIBILITY_WITH_HPP_FCL`，供 pinocchio `find_package(hpp-fcl)` 兼容。
- 编译 coal / pinocchio 需要系统 **assimp**、**octomap** 开发包（仅构建期 CMake 解析传递依赖）。

拷走使用：

```bash
cp -a 3rd_build/install/aarch64/ /path/to/3rd/aarch64/
```

### 同步 yaml-cpp 到 controller_component

**必须在目标架构环境构建**（Linux aarch64 容器内），不要用 macOS 本地产物覆盖 `3rdparty/yaml-cpp`。

```bash
cd controller_source/3rd_build

# 仅构建 yaml-cpp（无其他依赖，最快）
./build.sh fetch
./build.sh build --only yaml-cpp

# 拷贝预编译产物到组件目录
./stage_yaml_cpp_to_component.sh

# 验证
bash ../../inexus/components/controller_component/.local/test/build_smoke.sh

# 宿主机调用 wk_dev（推荐）
bash ../../inexus/components/controller_component/.local/test/run_smoke_wk_dev.sh
```

`stage_yaml_cpp_to_component.sh` 将 `install/<arch>/yaml-cpp/` 同步到
`inexus/components/controller_component/3rdparty/yaml-cpp/`（仅 `lib/` + `include/`）。

## 下游 CMake 集成

```cmake
set(THIRD_ROOT /path/to/3rd/aarch64)
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

链接进自己的 `.so` 时，各静态库均已 `-fPIC` 编译。

## 链接验证

```bash
cd 3rd_build/test_link
cmake -S . -B build
cmake --build build
./build/test_link
# 期望输出: pinocchio nq=0 placo wrap_angle(4.0)=-2.28319
```

## 逆解 Demo（placo IK）

`3rd_build/demo_ik/` 演示用 placo 对三关节机械臂做任务空间逆解：

- 加载 `models/arm3/robot.urdf`（3-DOF 平面臂）
- **任务**：末端位置、末端姿态（低权重）、关节姿态偏好、正则化
- 迭代 `solve(true)` 收敛到目标位姿

```bash
cd 3rd_build/demo_ik
cmake -S . -B build && cmake --build build
./build/demo_ik
```

示例输出：

```
Initial ee pos = [0.5, 0, 0]
Target ee pos = [0.420, 0.280, 0.000]
Final ee pos = [0.416, 0.277, 0.000]
Position error norm = 0.005 m
IK demo OK
```

## 版本锁定

版本以 placo v0.9.23 的 `pyproject.toml` 为准，详见 `3rd_build/versions.yaml`。
