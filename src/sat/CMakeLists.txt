option(Z3_GPU "Build with GPU (CUDA) support" ON)

# BooledASS CUDA detection
if (Z3_GPU)
    find_program(NVCC_PATH nvcc)
    if (NVCC_PATH)
        set(NVCC "${NVCC_PATH}")
    else()
        set(CUDA_TOOLKIT_ROOT "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2")
        set(NVCC "${CUDA_TOOLKIT_ROOT}/bin/nvcc.exe")
    endif()

    if (EXISTS "${NVCC}")
        set(WITH_CUDA ON CACHE INTERNAL "Build with CUDA support")
    else()
        set(WITH_CUDA OFF CACHE INTERNAL "Build with CUDA support")
    endif()
else()
    set(WITH_CUDA OFF CACHE INTERNAL "Build with CUDA support")
endif()

set(sat_extra_sources "")
if (NOT WITH_CUDA)
    list(APPEND sat_extra_sources booledass_stubs.cpp)
endif()

z3_add_component(sat
  SOURCES
    dimacs.cpp
    sat_aig_finder.cpp
    sat_anf_simplifier.cpp
    sat_asymm_branch.cpp
    sat_bcd.cpp
    sat_big.cpp
    sat_clause.cpp
    sat_clause_set.cpp
    sat_clause_use_list.cpp
    sat_cleaner.cpp
    sat_config.cpp
    sat_ddfw_wrapper.cpp    
    sat_drat.cpp
    sat_elim_eqs.cpp
    sat_gc.cpp
    sat_integrity_checker.cpp
    sat_local_search.cpp
    sat_lookahead.cpp
    sat_model_converter.cpp
    sat_mus.cpp
    sat_npn3_finder.cpp
    sat_parallel.cpp
    sat_prob.cpp
    sat_probing.cpp
    sat_proof_trim.cpp
    sat_scc.cpp
    sat_simplifier.cpp
    sat_solver.cpp
    sat_watched.cpp
    sat_xor_finder.cpp
    ${sat_extra_sources}
  COMPONENT_DEPENDENCIES
    util
    dd
    grobner
    params
  PYG_FILES
    sat_asymm_branch_params.pyg
    sat_scc_params.pyg
    sat_simplifier_params.pyg
)

# BooledASS GPU engine — compiled as pure C to avoid C++/MSVC header conflicts
set_source_files_properties(booledass.c PROPERTIES LANGUAGE C)
add_library(booledass_engine OBJECT booledass.c)
set_target_properties(booledass_engine PROPERTIES LINKER_LANGUAGE C C_STANDARD 11)
if (MSVC)
    target_compile_options(booledass_engine PRIVATE /TC /FS)
endif()

# BooledASS CUDA kernels — compiled with nvcc separately
if (WITH_CUDA)
    set(CUDA_KERNEL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/booledass_kernels.cu")
    set(CUDA_KERNEL_OBJ "${CMAKE_CURRENT_BINARY_DIR}/booledass_kernels.obj")
    
    set(NVCC_HOST_FLAGS "")
    if (MSVC)
        set(NVCC_HOST_FLAGS --compiler-options "/FS /MD /DNDEBUG /D_ITERATOR_DEBUG_LEVEL=0" -Xcompiler "/W0")
    endif()

    add_custom_command(
      OUTPUT "${CUDA_KERNEL_OBJ}"
      COMMAND "${NVCC}"
        -c "${CUDA_KERNEL_SRC}"
        -o "${CUDA_KERNEL_OBJ}"
        -gencode=arch=compute_75,code=sm_75
        -gencode=arch=compute_80,code=sm_80
        -gencode=arch=compute_86,code=sm_86
        -gencode=arch=compute_89,code=sm_89
        -gencode=arch=compute_90,code=compute_90
        -O2
        ${NVCC_HOST_FLAGS}
      DEPENDS "${CUDA_KERNEL_SRC}"
      COMMENT "Compiling CUDA BCP kernels (Release: sm_75, sm_80, sm_86, sm_89, sm_90)"
      VERBATIM
    )
    add_custom_target(booledass_cuda_kernels DEPENDS "${CUDA_KERNEL_OBJ}")
    add_dependencies(booledass_engine booledass_cuda_kernels)
endif()

