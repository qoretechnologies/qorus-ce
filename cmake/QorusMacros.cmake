if (${QORE_BUILD_TYPE_LWR} MATCHES "debug")
    set(QORUS_MAKE_SOURCE_ARGS -d)
    add_definitions(-DDEBUG)
endif()

# Create C++ files from Qore source code.
# Arguments:
#  _cpp_files : output list of filenames created in CMAKE_BINARY_DIR.
#               file mask: x_<original_fname>.cpp
#  _inputs : input list provided as value ("${FOO}")
#
MACRO (QORUS_QORE2CPP _cpp_files _inputs )
  FOREACH (it ${_inputs})
    #message(STATUS "QPP1: ${it}")
    GET_FILENAME_COMPONENT(_outfile ${it} NAME)
    GET_FILENAME_COMPONENT(_infile ${it} ABSOLUTE)
    SET(_cppfile ${CMAKE_BINARY_DIR}/x_${_outfile}.cpp)
#    message(STATUS "Qore to c++: ${_infile} -> ${_outfile}")

    ADD_CUSTOM_COMMAND(OUTPUT ${_cppfile}
            COMMAND QORE_INCLUDE_DIR=${QORE_INCLUDE_DIR_PATHS} QORE_MODULE_DIR=${QORE_MODULE_DIR_PATHS} ${CMAKE_SOURCE_DIR}/exec/make-source.q ${QORUS_MAKE_SOURCE_ARGS}
            ARGS ${make_source_opts} ${_infile}
            MAIN_DEPENDENCY ${_infile}
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
            VERBATIM
        )

    SET(${_cpp_files} ${${_cpp_files}} ${_cppfile})
  ENDFOREACH (it)

ENDMACRO (QORUS_QORE2CPP)

# Create C++ files from Qore module code.
# Arguments:
#  _cpp_files : output list of filenames created in CMAKE_BINARY_DIR.
#               file mask: x_<original_fname>.cpp
#  _inputs : input list provided as value ("${FOO}")
#
MACRO (QORUS_QOREMOD2CPP _cpp_files _inputs )
  FOREACH (it ${_inputs})
    #message(STATUS "QPP1: ${it}")
    GET_FILENAME_COMPONENT(_outfile ${it} NAME)
    GET_FILENAME_COMPONENT(_infile ${it} ABSOLUTE)
    SET(_cppfile ${CMAKE_BINARY_DIR}/x_${_outfile}.cpp)
#    message(STATUS "Qore to c++: ${_infile} -> ${_outfile}")

    ADD_CUSTOM_COMMAND(OUTPUT ${_cppfile}
            COMMAND QORE_INCLUDE_DIR=${QORE_INCLUDE_DIR_PATHS} QORE_MODULE_DIR=${QORE_MODULE_DIR_PATHS} ${CMAKE_SOURCE_DIR}/exec/make-source.q ${QORUS_MAKE_SOURCE_ARGS}
            ARGS -m ${_infile}
            MAIN_DEPENDENCY ${_infile}
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
            VERBATIM
        )

    SET(${_cpp_files} ${${_cpp_files}} ${_cppfile})
  ENDFOREACH (it)
ENDMACRO (QORUS_QOREMOD2CPP)

# call tools/qccp against list of liles
# Arguments:
#  _qccp_files : output list of filenames created in CMAKE_BINARY_DIR.
#  _inputs : input list provided as value ("${FOO}")
#
MACRO (QORUS_QCCP _qccp_files _inputs )
  FOREACH (it ${_inputs})
    GET_FILENAME_COMPONENT(_outfile ${it} NAME)
    GET_FILENAME_COMPONENT(_infile ${it} ABSOLUTE)
    SET(_qccpfile ${CMAKE_BINARY_DIR}/${_outfile})

    # ensure that qccp is run always even on install phase (pretty fast)
    # to have client module always up-to-date
    ADD_CUSTOM_TARGET(${_outfile} ALL
                QORE_INCLUDE_DIR=${QORE_INCLUDE_DIR_PATHS} QORE_MODULE_DIR=${QORE_MODULE_DIR_PATHS} ${CMAKE_SOURCE_DIR}/tools/qccp ${_infile} ${CMAKE_BINARY_DIR}
            DEPENDS ${_infile}
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            COMMENT "qccp: ${_infile}"
            VERBATIM
        )

    SET(${_qccp_files} ${${_qccp_files}} ${_qccpfile})
  ENDFOREACH (it)
ENDMACRO (QORUS_QCCP)

# Get timestamp (epoch seconds) as integer.
# Arguments:
#  _result : output variable
MACRO(QORUS_BUILD_TIMESTAMP _result)
    execute_process(COMMAND "date" "+%s" OUTPUT_VARIABLE ${_result} OUTPUT_STRIP_TRAILING_WHITESPACE)
ENDMACRO(QORUS_BUILD_TIMESTAMP)

# Get git revision number calling 'git' internally
# Arguments:
#  _result : output variable
MACRO(QORUS_BUILD_GITVERSION _result)
    execute_process(COMMAND git rev-parse HEAD
                    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                    RESULT_VARIABLE _ret
                    OUTPUT_VARIABLE ${_result}
                    OUTPUT_STRIP_TRAILING_WHITESPACE)

    if (${_ret})
        message(WARNING "Getting tree revision failed; ignoring")
        set(${_result} "binary-release")
    endif()
ENDMACRO(QORUS_BUILD_GITVERSION)

# Process doxygen templates and source files for 'docs' target
# Arguments:
#  _outputs : output list of filenames created in CMAKE_BINARY_DIR/doxygen
#  _inputs : input list provided as value ("${FOO}")
MACRO (QORUS_DOC_API_FILTER _outputs _inputs )
    file(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/doxygen)

    foreach (it ${_inputs})
        if (IS_DIRECTORY ${CMAKE_SOURCE_DIR}/${it})
            #message(STATUS "dir: ${it}")
            file (GLOB it_dir_list "${CMAKE_SOURCE_DIR}/${it}/*")
            foreach (it_f ${it_dir_list})
                #message(STATUS "dir entry: ${it_f}")
                get_filename_component(_outfilename ${it_f} NAME)
                get_filename_component(_infile ${it_f} ABSOLUTE)
                # get the shortest file extension
                string(REGEX REPLACE "^.+(\\.[^.]+)$" "\\1" _ext ${_outfilename})
                set(_outfile ${CMAKE_CURRENT_BINARY_DIR}/doxygen/${_outfilename})
                string(REPLACE ".tmpl" "" _outfile ${_outfile})

                #message(STATUS "API> ${_outfile} ${_infile} ${_ext}")

                ADD_CUSTOM_COMMAND(OUTPUT ${_outfile}
                    COMMAND QORE_INCLUDE_DIR=${QORE_INCLUDE_DIR_PATHS} QORE_MODULE_DIR=${QORE_MODULE_DIR_PATHS} ${CMAKE_SOURCE_DIR}/doxygen/doxygen-api-filter.q --outdir=${CMAKE_CURRENT_BINARY_DIR}/doxygen ${_infile}
                    MAIN_DEPENDENCY ${_infile}
                    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/doxygen
                    VERBATIM
                )

                set(${_outputs} ${${_outputs}} ${_outfile})
            endforeach(it_f)
            continue()
        endif()
        #message(STATUS "NOT dir: ${it}")

        get_filename_component(_outfilename ${it} NAME)
        get_filename_component(_infile ${it} ABSOLUTE)
        # get the shortest file extension
        string(REGEX REPLACE "^.+(\\.[^.]+)$" "\\1" _ext ${_outfilename})
        set(_outfile ${CMAKE_CURRENT_BINARY_DIR}/doxygen/${_outfilename})
        string(REPLACE ".tmpl" "" _outfile ${_outfile})

        #message(STATUS "API> ${_outfile} ${_infile} ${_ext}")

        ADD_CUSTOM_COMMAND(OUTPUT ${_outfile}
            COMMAND QORE_INCLUDE_DIR=${QORE_INCLUDE_DIR_PATHS} QORE_MODULE_DIR=${QORE_MODULE_DIR_PATHS} ${CMAKE_SOURCE_DIR}/doxygen/doxygen-api-filter.q --outdir=${CMAKE_CURRENT_BINARY_DIR}/doxygen ${_infile}
            MAIN_DEPENDENCY ${_infile}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/doxygen
            VERBATIM
        )

        set(${_outputs} ${${_outputs}} ${_outfile})
    endforeach (it)

ENDMACRO (QORUS_DOC_API_FILTER)

# Process doxygen templates and source files for 'docs' target
# Arguments:
#  _outfile : output filename created in CMAKE_BINARY_DIR/doxygen
#  _inputs : input list provided as value ("${FOO}")
MACRO (QORUS_DOC_API_REST_FILTER _outfile _inputs)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/doxygen)

    # get a list of absolute file names for the input files
    foreach (it ${_inputs})
        get_filename_component(_infile ${it} ABSOLUTE)
        set(_inlist ${_inlist} ${_infile})
    endforeach (it)

    # get output file name
    set(_inarg ${_inputs})
    # macro arguments are not variable and can't be used directly with the list command
    list(GET _inarg 0 _rest_file)
    get_filename_component(_outfilename ${_rest_file} NAME)
    # get the shortest file extension
    string(REGEX REPLACE "^.+(\\.[^.]+)$" "\\1" _ext ${_outfilename})
    set(${_outfile} ${CMAKE_BINARY_DIR}/doxygen/${_outfilename})

    add_custom_command(OUTPUT ${${_outfile}} ${QORUS_ETC_REST_SCHEMA_TARGETS}
        COMMAND QORE_INCLUDE_DIR=${QORE_INCLUDE_DIR_PATHS} QORE_MODULE_DIR=${QORE_MODULE_DIR_PATHS}
            ${CMAKE_SOURCE_DIR}/doxygen/doxygen-api-filter.q
            --rest=${CMAKE_CURRENT_BINARY_DIR} --outdir=${CMAKE_CURRENT_BINARY_DIR}/doxygen ${_inlist}
        DEPENDS ${_inlist}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/doxygen
        VERBATIM
    )
    #message(STATUS "Qore to REST: MAIN: ${_rest_file} ORIG: ${_inputs} INPUT: ${_inlist} -> ${${_outfile}}")
ENDMACRO (QORUS_DOC_API_REST_FILTER)

MACRO (QORUS_PREPARE_JAVADOC_SRC _javadoc_src_files _inputs)
    FOREACH (it ${_inputs})
        get_filename_component(_outdir ${it} DIRECTORY)
        set(_outfile ${CMAKE_BINARY_DIR}/javadoc-src/${it})
        add_custom_command(OUTPUT ${_outfile}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/javadoc-src/${_outdir}
            COMMAND ${CMAKE_SOURCE_DIR}/tools/prepare-javadoc-src.sh ${CMAKE_SOURCE_DIR}/${it} ${_outfile}
        )
        set(${_javadoc_src_files} ${${_javadoc_src_files}} ${_outfile})
    ENDFOREACH (it)
ENDMACRO (QORUS_PREPARE_JAVADOC_SRC)

MACRO (QORUS_BUILD_JAVADOC _target_name _target_dir_name _javadoc_src_files)
    add_custom_target(${_target_name}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/javadoc/${_target_dir_name}
        COMMAND ${Java_JAVADOC_EXECUTABLE}
            -d ${CMAKE_BINARY_DIR}/javadoc/${_target_dir_name}
            -cp ${QORE_JNI_JAR}:${CMAKE_BINARY_DIR}/qorus-common.jar:${CMAKE_BINARY_DIR}/qorus-workflow.jar:${CMAKE_BINARY_DIR}/qorus-service.jar:${CMAKE_BINARY_DIR}/qorus-job.jar:${CMAKE_BINARY_DIR}/qorus-client.jar:${CMAKE_BINARY_DIR}/qorus-test.jar:${CMAKE_BINARY_DIR}/qorus-mapper.jar
            -tag "note:a:Note:"
            -tag "warning:a:Warning:"
            -Xdoclint:-missing
            ${_javadoc_src_files}
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        DEPENDS ${_javadoc_src_files} qorus-common qorus-workflow qorus-service qorus-job qorus-test qorus-mapper qorus-client
    )
ENDMACRO (QORUS_BUILD_JAVADOC)
