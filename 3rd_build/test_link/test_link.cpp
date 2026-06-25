#include <iostream>

#include <pinocchio/multibody/model.hpp>
#include <placo/tools/utils.h>

int main()
{
  pinocchio::Model model;
  const double wrapped = placo::tools::wrap_angle(4.0);
  std::cout << "pinocchio nq=" << model.nq << " placo wrap_angle(4.0)=" << wrapped << std::endl;
  return 0;
}
