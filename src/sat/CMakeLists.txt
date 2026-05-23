set(sat_extra_sources booledass_stubs.cpp)

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



