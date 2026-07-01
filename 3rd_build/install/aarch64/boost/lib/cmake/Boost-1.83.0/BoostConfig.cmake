set(Boost_FOUND TRUE)
set(Boost_VERSION_STRING "1.83.0")
set(_boost_root "${CMAKE_CURRENT_LIST_DIR}/../../..")
foreach(_comp filesystem system serialization)
  if(NOT TARGET Boost::${_comp})
    add_library(Boost::${_comp} STATIC IMPORTED)
    set_target_properties(Boost::${_comp} PROPERTIES
      IMPORTED_LOCATION "${_boost_root}/lib/libboost_${_comp}.a"
      INTERFACE_INCLUDE_DIRECTORIES "${_boost_root}/include")
  endif()
endforeach()
