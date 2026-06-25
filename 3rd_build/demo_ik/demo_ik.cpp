#include <cmath>
#include <iomanip>
#include <iostream>
#include <string>

#include <Eigen/Dense>

#include <placo/kinematics/kinematics_solver.h>
#include <placo/model/robot_wrapper.h>

#ifndef DEMO_MODEL_DIR
#define DEMO_MODEL_DIR "models/arm3"
#endif

static void print_pose(const std::string& label, const Eigen::Affine3d& T)
{
  const Eigen::Vector3d p = T.translation();
  std::cout << label << " pos = [" << p.x() << ", " << p.y() << ", " << p.z() << "]\n";
}

static void print_joints(placo::model::RobotWrapper& robot)
{
  std::cout << "  joints:";
  for (const auto& name : robot.joint_names())
  {
    std::cout << " " << name << "=" << std::fixed << std::setprecision(3) << robot.get_joint(name);
  }
  std::cout << "\n";
}

int main()
{
  using placo::kinematics::KinematicsSolver;
  using placo::model::RobotWrapper;

  RobotWrapper robot(DEMO_MODEL_DIR, RobotWrapper::IGNORE_COLLISIONS);
  KinematicsSolver solver(robot);

  solver.mask_fbase(true);
  solver.enable_joint_limits(true);

  robot.update_kinematics();
  const Eigen::Affine3d T_init = robot.get_T_world_frame("ee");
  print_pose("Initial ee", T_init);
  print_joints(robot);

  // Target: move end-effector to a reachable point in the XY plane.
  Eigen::Affine3d T_target = Eigen::Affine3d::Identity();
  T_target.translation() = Eigen::Vector3d(0.42, 0.28, 0.0);

  auto& ee_pos = solver.add_position_task("ee", T_target.translation());
  ee_pos.configure("ee_position", "soft", 100.0);

  auto& ee_ori = solver.add_orientation_task("ee", T_target.linear());
  ee_ori.configure("ee_orientation", "soft", 0.1);

  auto& posture = solver.add_joints_task();
  posture.set_joint("joint1", 0.0);
  posture.set_joint("joint2", 0.6);
  posture.set_joint("joint3", -0.4);
  posture.configure("posture", "soft", 0.01);

  auto& reg = solver.add_regularization_task(1e-4);
  reg.configure("reg", "soft", 1.0);

  print_pose("Target ee", T_target);

  constexpr int k_iters = 200;
  for (int i = 0; i < k_iters; ++i)
  {
    robot.update_kinematics();
    solver.solve(true);
  }

  robot.update_kinematics();
  const Eigen::Affine3d T_final = robot.get_T_world_frame("ee");
  const Eigen::Vector3d err = T_final.translation() - T_target.translation();

  print_pose("Final ee", T_final);
  print_joints(robot);
  std::cout << "Position error norm = " << err.norm() << " m\n";
  std::cout << "Position task error norm = " << ee_pos.error_norm() << " m\n";

  if (err.norm() < 2e-2)
  {
    std::cout << "IK demo OK\n";
    return 0;
  }

  std::cout << "IK demo FAILED (error too large)\n";
  return 1;
}
