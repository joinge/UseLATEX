# File: UseLATEX.cmake
# CMake script that builds Latex documents
# Version: 0.1
# Based on: Kenneth Moreland's UseLatex.cmake (version 2.7.2)
#           https://gitlab.kitware.com/kmorel/UseLATEX
# Edited by: Jo Inge Buskenes
#
# The following function is defined:
#
# add_latex_document(<tex_file>
#                    [BIBFILES <bib_files>]
#                    [INPUTS <input_tex_files>]
#                    [IMAGE_DIRS <image_directories>]
#                    [IMAGES <image_files>]
#                    [CONFIGURE <tex_files>]
#                    [DEPENDS <tex_files>]
#                    [MULTIBIB_NEWCITES <suffix_list>]
#                    [USE_BIBLATEX]
#                    [USE_INDEX]
#                    [INDEX_NAMES <index_names>]
#                    [USE_GLOSSARY] [USE_NOMENCL]
#                    [FORCE_PDF] [FORCE_DVI] [FORCE_HTML]
#                    [TARGET_NAME <name>]
#                    [INCLUDE_DIRECTORIES <directories>]
#                    [EXCLUDE_FROM_ALL]
#                    [EXCLUDE_FROM_DEFAULTS])
#       Adds targets that compile <tex_file>.  The latex output is placed
#       in LATEX_OUTPUT_PATH or CMAKE_CURRENT_BINARY_DIR if the former is
#       not set.  The latex program is picky about where files are located,
#       so all input files are copied from the source directory to the
#       output directory.  This includes the target tex file, any tex file
#       listed with the INPUTS option, the bibliography files listed with
#       the BIBFILES option, and any .cls, .bst, .clo, .sty, .ist, and .fd
#       files found in the current source directory.  Images found in the
#       IMAGE_DIRS directories or listed by IMAGES are also copied to the
#       output directory and converted to an appropriate format if necessary.
#       Any tex files also listed with the CONFIGURE option are also processed
#       with the CMake CONFIGURE_FILE command (with the @ONLY flag).  Any file
#       listed in CONFIGURE but not the target tex file or listed with INPUTS
#       has no effect. DEPENDS can be used to specify generated files that are
#       needed to compile the latex target.
#
#       The following targets are made. The name prefix is based off of the
#       base name of the tex file unless TARGET_NAME is specified. If
#       TARGET_NAME is specified, then that name is used for the targets.
#
#               name_dvi: Makes <name>.dvi
#               name_pdf: Makes <name>.pdf using pdflatex.
#               name_safepdf: Makes <name>.pdf using ps2pdf.  If using the
#                       default program arguments, this will ensure all fonts
#                       are embedded and no lossy compression has been
#                       performed on images.
#               name_ps: Makes <name>.ps
#               name_html: Makes <name>.html
#               name_auxclean: Deletes <name>.aux and other auxiliary files.
#                       This is sometimes necessary if a LaTeX error occurs
#                       and writes a bad aux file.  Unlike the regular clean
#                       target, it does not delete other input files, such as
#                       converted images, to save time on the rebuild.
#
#       Unless the EXCLUDE_FROM_ALL option is given, one of these targets
#       is added to the ALL target and built by default. Which target is
#       determined by the LATEX_DEFAULT_BUILD CMake variable. See the
#       documentation of that variable for more details.
#
#       Unless the EXCLUDE_FROM_DEFAULTS option is given, all these targets
#       are added as dependencies to targets named dvi, pdf, safepdf, ps,
#       html, and auxclean, respectively.
#
#       USE_BIBLATEX enables the use of biblatex/biber as an alternative to
#       bibtex. Bibtex remains the default if USE_BIBLATEX is not
#       specified.
#
#       If the argument USE_INDEX is given, then commands to build an index
#       are made. If the argument INDEX_NAMES is given, an index file is
#       generated for each name in this list. See the LaTeX package multind
#       for more information about how to generate multiple indices.
#
#       If the argument USE_GLOSSARY is given, then commands to
#       build a glossary are made.  If the argument MULTIBIB_NEWCITES is
#       given, then additional bibtex calls are added to the build to
#       support the extra auxiliary files created with the \newcite command
#       in the multibib package.
#
#       INCLUDE_DIRECTORIES provides a list of directories in which LaTeX
#       should look for input files. It accepts both files relative to the
#       binary directory and absolute paths.
#
# Alteration history:
#       First tree digits are Kenneth Moreland's UseLatex version.
#       Last digit is alteration version
#
# 2.7.2-1: Added Inscape conversion from SVGs


if(__USE_LATEX_INCLUDED)
  return()
endif()
set(__USE_LATEX_INCLUDED TRUE)

#############################################################################
# Find the location of myself while originally executing.  If you do this
# inside of a macro, it will recode where the macro was invoked.
#############################################################################
set(LATEX_USE_LATEX_LOCATION ${CMAKE_CURRENT_LIST_FILE}
  CACHE INTERNAL "Location of UseLATEX.cmake file." FORCE
  )

#############################################################################
# Generic helper functions
#############################################################################

include(CMakeParseArguments)

function(latex_list_contains var value)
  set(input_list ${ARGN})
  list(FIND input_list "${value}" index)
  if(index GREATER -1)
    set(${var} TRUE PARENT_SCOPE)
  else()
    set(${var} PARENT_SCOPE)
  endif()
endfunction(latex_list_contains)

# Match the contents of a file to a regular expression.
function(latex_file_match variable filename regexp default)
  # The FILE STRINGS command would be a bit better, but I'm not totally sure
  # the match will always be to a whole line, and I don't want to break things.
  file(READ ${filename} file_contents)
  string(REGEX MATCHALL "${regexp}"
    match_result ${file_contents}
    )
  if(match_result)
    set(${variable} "${match_result}" PARENT_SCOPE)
  else()
    set(${variable} "${default}" PARENT_SCOPE)
  endif()
endfunction(latex_file_match)

# A version of GET_FILENAME_COMPONENT that treats extensions after the last
# period rather than the first.  To the best of my knowledge, all filenames
# typically used by LaTeX, including image files, have small extensions
# after the last dot.
function(latex_get_filename_component varname filename type)
  set(result)
  if("${type}" STREQUAL "NAME_WE")
    get_filename_component(name ${filename} NAME)
    string(REGEX REPLACE "\\.[^.]*\$" "" result "${name}")
  elseif("${type}" STREQUAL "EXT")
    get_filename_component(name ${filename} NAME)
    string(REGEX MATCH "\\.[^.]*\$" result "${name}")
  else()
    get_filename_component(result ${filename} ${type})
  endif()
  set(${varname} "${result}" PARENT_SCOPE)
endfunction(latex_get_filename_component)

#############################################################################
# Functions that perform processing during a LaTeX build.
#############################################################################
function(latex_execute_latex)
  if(NOT LATEX_WORKING_DIRECTORY)
    message(SEND_ERROR "Need to define LATEX_WORKING_DIRECTORY")
  endif()

  if(NOT LATEX_FULL_COMMAND)
    message(SEND_ERROR "Need to define LATEX_FULL_COMMAND")
  endif()

  if(NOT LATEX_OUTPUT_FILE)
    message(SEND_ERROR "Need to define LATEX_OUTPUT_FILE")
  endif()

  if(NOT LATEX_LOG_FILE)
    message(SEND_ERROR "Need to define LATEX_LOG_FILE")
  endif()

  set(full_command_original "${LATEX_FULL_COMMAND}")

  # Chose the native method for parsing command arguments. Newer versions of
  # CMake allow you to just use NATIVE_COMMAND.
  if (CMAKE_VERSION VERSION_GREATER 3.8)
    set(separate_arguments_mode NATIVE_COMMAND)
  else()
    if (WIN32)
      set(separate_arguments_mode WINDOWS_COMMAND)
    else()
      set(separate_arguments_mode UNIX_COMMAND)
    endif()
  endif()

  # Preps variables for use in execute_process.
  # Even though we expect LATEX_WORKING_DIRECTORY to have a single "argument,"
  # we also want to make sure that we strip out any escape characters that can
  # foul up the WORKING_DIRECTORY argument.
  separate_arguments(LATEX_FULL_COMMAND UNIX_COMMAND "${LATEX_FULL_COMMAND}")
  separate_arguments(LATEX_WORKING_DIRECTORY_SEP UNIX_COMMAND "${LATEX_WORKING_DIRECTORY}")

  execute_process(
    COMMAND ${LATEX_FULL_COMMAND}
    WORKING_DIRECTORY "${LATEX_WORKING_DIRECTORY_SEP}"
    RESULT_VARIABLE execute_result
    OUTPUT_VARIABLE ignore
    ERROR_VARIABLE ignore
    )

  if(NOT ${execute_result} EQUAL 0)
    # LaTeX tends to write a file when a failure happens. Delete that file so
    # that LaTeX will run again.
    separate_arguments(LATEX_OUTPUT_FILE_SEP UNIX_COMMAND "${LATEX_OUTPUT_FILE}")
    file(REMOVE "${LATEX_WORKING_DIRECTORY_SEP}/${LATEX_OUTPUT_FILE_SEP}")

    message("\n\nLaTeX command failed")
    message("${full_command_original}")
    message("Log output:")
    separate_arguments(LATEX_LOG_FILE_SEP UNIX_COMMAND "${LATEX_LOG_FILE}")
    file(READ "${LATEX_WORKING_DIRECTORY_SEP}/${LATEX_LOG_FILE_SEP}" log_output)
    message("${log_output}")
    message(FATAL_ERROR "Executed LaTeX, but LaTeX returned an error.")
  endif()
endfunction(latex_execute_latex)

function(latex_makeglossaries)
  # This is really a bare bones port of the makeglossaries perl script into
  # CMake scripting.
  message("**************************** In makeglossaries")
  if(NOT LATEX_TARGET)
    message(SEND_ERROR "Need to define LATEX_TARGET")
  endif()

  set(aux_file ${LATEX_TARGET}.aux)

  if(NOT EXISTS ${aux_file})
    message(SEND_ERROR "${aux_file} does not exist.  Run latex on your target file.")
  endif()

  latex_file_match(newglossary_lines ${aux_file}
    "@newglossary[ \t]*{([^}]*)}{([^}]*)}{([^}]*)}{([^}]*)}"
    "@newglossary{main}{glg}{gls}{glo}"
    )

  latex_file_match(istfile_line ${aux_file}
    "@istfilename[ \t]*{([^}]*)}"
    "@istfilename{${LATEX_TARGET}.ist}"
    )
  string(REGEX REPLACE "@istfilename[ \t]*{([^}]*)}" "\\1"
    istfile ${istfile_line}
    )

  string(REGEX MATCH ".*\\.xdy" use_xindy "${istfile}")
  if(use_xindy)
    message("*************** Using xindy")
    if(NOT XINDY_COMPILER)
      message(SEND_ERROR "Need to define XINDY_COMPILER")
    endif()
  else()
    message("*************** Using makeindex")
    if(NOT MAKEINDEX_COMPILER)
      message(SEND_ERROR "Need to define MAKEINDEX_COMPILER")
    endif()
  endif()

  foreach(newglossary ${newglossary_lines})
    string(REGEX REPLACE
      "@newglossary[ \t]*{([^}]*)}{([^}]*)}{([^}]*)}{([^}]*)}"
      "\\1" glossary_name ${newglossary}
      )
    string(REGEX REPLACE
      "@newglossary[ \t]*{([^}]*)}{([^}]*)}{([^}]*)}{([^}]*)}"
      "${LATEX_TARGET}.\\2" glossary_log ${newglossary}
      )
    string(REGEX REPLACE
      "@newglossary[ \t]*{([^}]*)}{([^}]*)}{([^}]*)}{([^}]*)}"
      "${LATEX_TARGET}.\\3" glossary_out ${newglossary}
      )
    string(REGEX REPLACE
      "@newglossary[ \t]*{([^}]*)}{([^}]*)}{([^}]*)}{([^}]*)}"
      "${LATEX_TARGET}.\\4" glossary_in ${newglossary}
      )

    if(use_xindy)
      latex_file_match(xdylanguage_line ${aux_file}
        "@xdylanguage[ \t]*{${glossary_name}}{([^}]*)}"
        "@xdylanguage{${glossary_name}}{english}"
        )
      string(REGEX REPLACE
        "@xdylanguage[ \t]*{${glossary_name}}{([^}]*)}"
        "\\1"
        language
        ${xdylanguage_line}
        )
      # What crazy person makes a LaTeX index generator that uses different
      # identifiers for language than babel (or at least does not support
      # the old ones)?
      if(${language} STREQUAL "frenchb")
        set(language "french")
      elseif(${language} MATCHES "^n?germanb?$")
        set(language "german")
      elseif(${language} STREQUAL "magyar")
        set(language "hungarian")
      elseif(${language} STREQUAL "lsorbian")
        set(language "lower-sorbian")
      elseif(${language} STREQUAL "norsk")
        set(language "norwegian")
      elseif(${language} STREQUAL "portuges")
        set(language "portuguese")
      elseif(${language} STREQUAL "russianb")
        set(language "russian")
      elseif(${language} STREQUAL "slovene")
        set(language "slovenian")
      elseif(${language} STREQUAL "ukraineb")
        set(language "ukrainian")
      elseif(${language} STREQUAL "usorbian")
        set(language "upper-sorbian")
      endif()
      if(language)
        set(language_flags "-L ${language}")
      else()
        set(language_flags "")
      endif()

      latex_file_match(codepage_line ${aux_file}
        "@gls@codepage[ \t]*{${glossary_name}}{([^}]*)}"
        "@gls@codepage{${glossary_name}}{utf}"
        )
      string(REGEX REPLACE
        "@gls@codepage[ \t]*{${glossary_name}}{([^}]*)}"
        "\\1"
        codepage
        ${codepage_line}
        )
      if(codepage)
        set(codepage_flags "-C ${codepage}")
      else()
        # Ideally, we would check that the language is compatible with the
        # default codepage, but I'm hoping that distributions will be smart
        # enough to specify their own codepage.  I know, it's asking a lot.
        set(codepage_flags "")
      endif()

      message("${XINDY_COMPILER} ${MAKEGLOSSARIES_COMPILER_ARGS} ${language_flags} ${codepage_flags} -I xindy -M ${glossary_name} -t ${glossary_log} -o ${glossary_out} ${glossary_in}"
        )
      exec_program(${XINDY_COMPILER}
        ARGS ${MAKEGLOSSARIES_COMPILER_ARGS}
          ${language_flags}
          ${codepage_flags}
          -I xindy
          -M ${glossary_name}
          -t ${glossary_log}
          -o ${glossary_out}
          ${glossary_in}
        OUTPUT_VARIABLE xindy_output
        )
      message("${xindy_output}")

      # So, it is possible (perhaps common?) for aux files to specify a
      # language and codepage that are incompatible with each other.  Check
      # for that condition, and if it happens run again with the default
      # codepage.
      if("${xindy_output}" MATCHES "^Cannot locate xindy module for language (.+) in codepage (.+)\\.$")
        message("*************** Retrying xindy with default codepage.")
        exec_program(${XINDY_COMPILER}
          ARGS ${MAKEGLOSSARIES_COMPILER_ARGS}
            ${language_flags}
            -I xindy
            -M ${glossary_name}
            -t ${glossary_log}
            -o ${glossary_out}
            ${glossary_in}
          )
      endif()

    else()
      message("${MAKEINDEX_COMPILER} ${MAKEGLOSSARIES_COMPILER_ARGS} -s ${istfile} -t ${glossary_log} -o ${glossary_out} ${glossary_in}")
      exec_program(${MAKEINDEX_COMPILER} ARGS ${MAKEGLOSSARIES_COMPILER_ARGS}
        -s ${istfile} -t ${glossary_log} -o ${glossary_out} ${glossary_in}
        )
    endif()

  endforeach(newglossary)
endfunction(latex_makeglossaries)

function(latex_makenomenclature)
  message("**************************** In makenomenclature")
  if(NOT LATEX_TARGET)
    message(SEND_ERROR "Need to define LATEX_TARGET")
  endif()

  if(NOT MAKEINDEX_COMPILER)
    message(SEND_ERROR "Need to define MAKEINDEX_COMPILER")
  endif()

  set(nomencl_out ${LATEX_TARGET}.nls)
  set(nomencl_in ${LATEX_TARGET}.nlo)

  exec_program(${MAKEINDEX_COMPILER} ARGS ${MAKENOMENCLATURE_COMPILER_ARGS}
    ${nomencl_in} -s "nomencl.ist" -o ${nomencl_out}
    )
endfunction(latex_makenomenclature)

function(latex_correct_synctex)
  message("**************************** In correct SyncTeX")
  if(NOT LATEX_TARGET)
    message(SEND_ERROR "Need to define LATEX_TARGET")
  endif()

  if(NOT GZIP)
    message(SEND_ERROR "Need to define GZIP")
  endif()

  if(NOT LATEX_SOURCE_DIRECTORY)
    message(SEND_ERROR "Need to define LATEX_SOURCE_DIRECTORY")
  endif()

  if(NOT LATEX_BINARY_DIRECTORY)
    message(SEND_ERROR "Need to define LATEX_BINARY_DIRECTORY")
  endif()
  message("${LATEX_BINARY_DIRECTORY}")
  message("${LATEX_SOURCE_DIRECTORY}")

  set(synctex_file ${LATEX_BINARY_DIRECTORY}/${LATEX_TARGET}.synctex)
  set(synctex_file_gz ${synctex_file}.gz)

  if(EXISTS ${synctex_file_gz})

    message("Making backup of synctex file.")
    configure_file(${synctex_file_gz} ${synctex_file}.bak.gz COPYONLY)

    message("Uncompressing synctex file.")
    exec_program(${GZIP}
      ARGS --decompress ${synctex_file_gz}
      )

    message("Reading synctex file.")
    file(READ ${synctex_file} synctex_data)

    message("Replacing output paths with input paths.")
    foreach(extension tex cls bst clo sty ist fd)
      # Relative paths
      string(REGEX REPLACE
        "(Input:[0-9]+:)([^/\n][^\n]\\.${extension}*)"
        "\\1${LATEX_SOURCE_DIRECTORY}/\\2"
        synctex_data
        "${synctex_data}"
        )

      # Absolute paths
      string(REGEX REPLACE
        "(Input:[0-9]+:)${LATEX_BINARY_DIRECTORY}([^\n]*\\.${extension})"
        "\\1${LATEX_SOURCE_DIRECTORY}\\2"
        synctex_data
        "${synctex_data}"
        )
    endforeach(extension)

    message("Writing synctex file.")
    file(WRITE ${synctex_file} "${synctex_data}")

    message("Compressing synctex file.")
    exec_program(${GZIP}
      ARGS ${synctex_file}
      )

  else()

    message(SEND_ERROR "File ${synctex_file_gz} not found.  Perhaps synctex is not supported by your LaTeX compiler.")

  endif()

endfunction(latex_correct_synctex)

function(latex_check_important_warnings)
  # Check for biber warnings/errors if that was run
  set(bib_log_file ${LATEX_TARGET}.blg)
  if(EXISTS ${bib_log_file})
    file(READ ${bib_log_file} bib_log)
    if(bib_log MATCHES "INFO - This is Biber")
      message("\nChecking ${bib_log_file} for Biber warnings/errors.")

      string(REGEX MATCHALL
        "[A-Z]+ - [^\n]*"
        biber_messages
        "${bib_log}")

      set(found_error)
      foreach(message ${biber_messages})
        if(NOT message MATCHES  "^INFO - ")
          set(found_error TRUE)
          message("${message}")
        endif()
      endforeach(message)

      if(found_error)
        latex_get_filename_component(log_file_path ${bib_log_file} ABSOLUTE)
        message("\nConsult ${log_file_path} for more information on Biber output.")
      else()
        message("No known important Biber output found.")
      endif(found_error)
    else() # Biber output not in log file
      message("Skipping biber checks (biber not used)")
    endif()
  else() # No bib log file
    message("Skipping bibliography checks (not run)")
  endif()

  set(log_file ${LATEX_TARGET}.log)

  message("\nChecking ${log_file} for important warnings.")
  if(NOT LATEX_TARGET)
    message(SEND_ERROR "Need to define LATEX_TARGET")
  endif()

  if(NOT EXISTS ${log_file})
    message("Could not find log file: ${log_file}")
    return()
  endif()

  set(found_error)

  file(READ ${log_file} log)

  # Check for declared LaTeX warnings
  string(REGEX MATCHALL
    "\nLaTeX Warning:[^\n]*"
    latex_warnings
    "${log}")
  # Ignore warnings considered harmless
  list(FILTER latex_warnings EXCLUDE REGEX
    "LaTeX Warning: Font shape declaration has incorrect series value `mc'."
    )
  if(latex_warnings)
    set(found_error TRUE)
    message("\nFound declared LaTeX warnings.")
    foreach(warning ${latex_warnings})
      string(STRIP "${warning}" warning_no_newline)
      message("${warning_no_newline}")
    endforeach(warning)
  endif()

  # Check for natbib warnings
  string(REGEX MATCHALL
    "\nPackage natbib Warning:[^\n]*"
    natbib_warnings
    "${log}")
  if(natbib_warnings)
    set(found_error TRUE)
    message("\nFound natbib package warnings.")
    foreach(warning ${natbib_warnings})
      string(STRIP "${warning}" warning_no_newline)
      message("${warning_no_newline}")
    endforeach(warning)
  endif()

  # Check for overfull
  string(REGEX MATCHALL
    "\nOverfull[^\n]*"
    overfull_warnings
    "${log}")
  if(overfull_warnings)
    set(found_error TRUE)
    message("\nFound overfull warnings. These are indicative of layout errors.")
    foreach(warning ${overfull_warnings})
      string(STRIP "${warning}" warning_no_newline)
      message("${warning_no_newline}")
    endforeach(warning)
  endif()

  # Check for invalid characters
  string(REGEX MATCHALL
    "\nMissing character:[^\n]*"
    invalid_character_warnings
    "${log}")
  if(invalid_character_warnings)
    set(found_error TRUE)
    message("\nFound invalid character warnings. These characters are likely not printed correctly.")
    foreach(warning ${invalid_character_warnings})
      string(STRIP "${warning}" warning_no_newline)
      message("${warning_no_newline}")
    endforeach(warning)
  endif()

  if(found_error)
    latex_get_filename_component(log_file_path ${log_file} ABSOLUTE)
    message("\nConsult ${log_file_path} for more information on LaTeX build.")
  else()
    message("No known important warnings found.")
  endif(found_error)
endfunction(latex_check_important_warnings)

#############################################################################
# Helper functions for establishing LaTeX build.
#############################################################################

function(latex_needit VAR NAME)
  if(NOT ${VAR})
    message(SEND_ERROR "I need the ${NAME} command.")
  endif()
endfunction(latex_needit)

function(latex_wantit VAR NAME)
  if(NOT ${VAR})
    message(STATUS "I could not find the ${NAME} command.")
  endif()
endfunction(latex_wantit)

function(latex_setup_variables)
  set(LATEX_OUTPUT_PATH "${LATEX_OUTPUT_PATH}"
    CACHE PATH "If non empty, specifies the location to place LaTeX output."
    )

  find_package(LATEX)

  find_program(XINDY_COMPILER
    NAME xindy
    PATHS ${MIKTEX_BINARY_PATH} /usr/bin
    )

  find_package(UnixCommands)

  find_program(PDFTOPS_CONVERTER
    NAMES pdftops
    DOC "The pdf to ps converter program from the Poppler package."
    )

  find_program(HTLATEX_COMPILER
    NAMES htlatex
    PATHS ${MIKTEX_BINARY_PATH}
      /usr/bin
    )

  mark_as_advanced(
    LATEX_COMPILER
    PDFLATEX_COMPILER
    BIBTEX_COMPILER
    BIBER_COMPILER
    MAKEINDEX_COMPILER
    XINDY_COMPILER
    DVIPS_CONVERTER
    PS2PDF_CONVERTER
    PDFTOPS_CONVERTER
    LATEX2HTML_CONVERTER
    HTLATEX_COMPILER
    )

  latex_needit(LATEX_COMPILER latex)
  latex_wantit(PDFLATEX_COMPILER pdflatex)
  latex_wantit(HTLATEX_COMPILER htlatex)
  latex_needit(BIBTEX_COMPILER bibtex)
  latex_wantit(BIBER_COMPILER biber)
  latex_needit(MAKEINDEX_COMPILER makeindex)
  latex_wantit(DVIPS_CONVERTER dvips)
  latex_wantit(PS2PDF_CONVERTER ps2pdf)
  latex_wantit(PDFTOPS_CONVERTER pdftops)

  set(LATEX_COMPILER_FLAGS "-interaction=batchmode -file-line-error"
    CACHE STRING "Flags passed to latex.")
  set(PDFLATEX_COMPILER_FLAGS ${LATEX_COMPILER_FLAGS}
    CACHE STRING "Flags passed to pdflatex.")
  set(HTLATEX_COMPILER_TEX4HT_FLAGS "html"
    CACHE STRING "Options for the tex4ht.sty and *.4ht style files.")
  set(HTLATEX_COMPILER_TEX4HT_POSTPROCESSOR_FLAGS ""
    CACHE STRING "Options for the text4ht postprocessor.")
  set(HTLATEX_COMPILER_T4HT_POSTPROCESSOR_FLAGS ""
    CACHE STRING "Options for the t4ht postprocessor.")
  set(HTLATEX_COMPILER_LATEX_FLAGS ${LATEX_COMPILER_FLAGS}
    CACHE STRING "Flags passed from htlatex to the LaTeX compiler.")
  set(LATEX_SYNCTEX_FLAGS "-synctex=1"
    CACHE STRING "latex/pdflatex flags used to create synctex file.")
  set(BIBTEX_COMPILER_FLAGS ""
    CACHE STRING "Flags passed to bibtex.")
  set(BIBER_COMPILER_FLAGS ""
    CACHE STRING "Flags passed to biber.")
  set(MAKEINDEX_COMPILER_FLAGS ""
    CACHE STRING "Flags passed to makeindex.")
  set(MAKEGLOSSARIES_COMPILER_FLAGS ""
    CACHE STRING "Flags passed to makeglossaries.")
  set(MAKENOMENCLATURE_COMPILER_FLAGS ""
    CACHE STRING "Flags passed to makenomenclature.")
  set(DVIPS_CONVERTER_FLAGS "-Ppdf -G0 -t letter"
    CACHE STRING "Flags passed to dvips.")
  if(NOT WIN32)
    set(PS2PDF_CONVERTER_FLAGS "-dMaxSubsetPct=100 -dCompatibilityLevel=1.3 -dSubsetFonts=true -dEmbedAllFonts=true -dAutoFilterColorImages=false -dAutoFilterGrayImages=false -dColorImageFilter=/FlateEncode -dGrayImageFilter=/FlateEncode -dMonoImageFilter=/FlateEncode"
      CACHE STRING "Flags passed to ps2pdf.")
  else()
    # Most windows ports of ghostscript utilities use .bat files for ps2pdf
    # commands. bat scripts interpret "=" as a special character and separate
    # those arguments. To get around this, the ghostscript utilities also
    # support using "#" in place of "=".
    set(PS2PDF_CONVERTER_FLAGS "-dMaxSubsetPct#100 -dCompatibilityLevel#1.3 -dSubsetFonts#true -dEmbedAllFonts#true -dAutoFilterColorImages#false -dAutoFilterGrayImages#false -dColorImageFilter#/FlateEncode -dGrayImageFilter#/FlateEncode -dMonoImageFilter#/FlateEncode"
      CACHE STRING "Flags passed to ps2pdf.")
  endif()
  set(PDFTOPS_CONVERTER_FLAGS ""
    CACHE STRING "Flags passed to pdftops.")
  mark_as_advanced(
    LATEX_COMPILER_FLAGS
    PDFLATEX_COMPILER_FLAGS
    HTLATEX_COMPILER_TEX4HT_FLAGS
    HTLATEX_COMPILER_TEX4HT_POSTPROCESSOR_FLAGS
    HTLATEX_COMPILER_T4HT_POSTPROCESSOR_FLAGS
    HTLATEX_COMPILER_LATEX_FLAGS
    LATEX_SYNCTEX_FLAGS
    BIBTEX_COMPILER_FLAGS
    BIBER_COMPILER_FLAGS
    MAKEINDEX_COMPILER_FLAGS
    MAKEGLOSSARIES_COMPILER_FLAGS
    MAKENOMENCLATURE_COMPILER_FLAGS
    DVIPS_CONVERTER_FLAGS
    PS2PDF_CONVERTER_FLAGS
    PDFTOPS_CONVERTER_FLAGS
    )

  # Because it is easier to type, the flags variables are entered as
  # space-separated strings much like you would in a shell. However, when
  # using a CMake command to execute a program, it works better to hold the
  # arguments in semicolon-separated lists (otherwise the whole string will
  # be interpreted as a single argument). Use the separate_arguments to
  # convert the space-separated strings to semicolon-separated lists.
  separate_arguments(LATEX_COMPILER_FLAGS)
  separate_arguments(PDFLATEX_COMPILER_FLAGS)
  separate_arguments(HTLATEX_COMPILER_LATEX_FLAGS)
  separate_arguments(LATEX_SYNCTEX_FLAGS)
  separate_arguments(BIBTEX_COMPILER_FLAGS)
  separate_arguments(BIBER_COMPILER_FLAGS)
  separate_arguments(MAKEINDEX_COMPILER_FLAGS)
  separate_arguments(MAKEGLOSSARIES_COMPILER_FLAGS)
  separate_arguments(MAKENOMENCLATURE_COMPILER_FLAGS)
  separate_arguments(DVIPS_CONVERTER_FLAGS)
  separate_arguments(PS2PDF_CONVERTER_FLAGS)
  separate_arguments(PDFTOPS_CONVERTER_FLAGS)

  # Not quite done. When you call separate_arguments on a cache variable,
  # the result is written to a local variable. That local variable goes
  # away when this function returns (which is before any of them are used).
  # So, copy these variables with local scope to cache variables with
  # global scope.
  set(LATEX_COMPILER_ARGS "${LATEX_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(PDFLATEX_COMPILER_ARGS "${PDFLATEX_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(HTLATEX_COMPILER_ARGS "${HTLATEX_COMPILER_LATEX_FLAGS}" CACHE INTERNAL "")
  set(LATEX_SYNCTEX_ARGS "${LATEX_SYNCTEX_FLAGS}" CACHE INTERNAL "")
  set(BIBTEX_COMPILER_ARGS "${BIBTEX_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(BIBER_COMPILER_ARGS "${BIBER_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(MAKEINDEX_COMPILER_ARGS "${MAKEINDEX_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(MAKEGLOSSARIES_COMPILER_ARGS "${MAKEGLOSSARIES_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(MAKENOMENCLATURE_COMPILER_ARGS "${MAKENOMENCLATURE_COMPILER_FLAGS}" CACHE INTERNAL "")
  set(DVIPS_CONVERTER_ARGS "${DVIPS_CONVERTER_FLAGS}" CACHE INTERNAL "")
  set(PS2PDF_CONVERTER_ARGS "${PS2PDF_CONVERTER_FLAGS}" CACHE INTERNAL "")
  set(PDFTOPS_CONVERTER_ARGS "${PDFTOPS_CONVERTER_FLAGS}" CACHE INTERNAL "")

  find_program(IMAGEMAGICK_CONVERT
    NAMES magick convert
    DOC "The convert program that comes with ImageMagick (available at http://www.imagemagick.org)."
    )
  mark_as_advanced(IMAGEMAGICK_CONVERT)

  if(DEFINED ENV{LATEX_DEFAULT_BUILD})
    set(default_build $ENV{LATEX_DEFAULT_BUILD})
  else()
    set(default_build pdf)
  endif()

  set(LATEX_DEFAULT_BUILD "${default_build}" CACHE STRING
    "Choose the default type of LaTeX build. Valid options are pdf, dvi, ps, safepdf, html"
    )
  set_property(CACHE LATEX_DEFAULT_BUILD
    PROPERTY STRINGS pdf dvi ps safepdf html
    )

  option(LATEX_USE_SYNCTEX
    "If on, have LaTeX generate a synctex file, which WYSIWYG editors can use to correlate output files like dvi and pdf with the lines of LaTeX source that generates them.  In addition to adding the LATEX_SYNCTEX_FLAGS to the command line, this option also adds build commands that \"corrects\" the resulting synctex file to point to the original LaTeX files rather than those generated by UseLATEX.cmake."
    OFF
    )

  option(LATEX_SMALL_IMAGES
    "If on, the raster images will be converted to 1/6 the original size.  This is because papers usually require 600 dpi images whereas most monitors only require at most 96 dpi.  Thus, smaller images make smaller files for web distribution and can make it faster to read dvi files."
    OFF)
  if(LATEX_SMALL_IMAGES)
    set(LATEX_RASTER_SCALE 16 PARENT_SCOPE)
    set(LATEX_OPPOSITE_RASTER_SCALE 100 PARENT_SCOPE)
  else()
    set(LATEX_RASTER_SCALE 100 PARENT_SCOPE)
    set(LATEX_OPPOSITE_RASTER_SCALE 16 PARENT_SCOPE)
  endif()

  # Just holds extensions for known image types.  They should all be lower case.
  # For historical reasons, these are all declared in the global scope.
  set(LATEX_DVI_VECTOR_IMAGE_EXTENSIONS .eps CACHE INTERNAL "")
  set(LATEX_DVI_RASTER_IMAGE_EXTENSIONS CACHE INTERNAL "")
  set(LATEX_DVI_IMAGE_EXTENSIONS
    ${LATEX_DVI_VECTOR_IMAGE_EXTENSIONS}
    ${LATEX_DVI_RASTER_IMAGE_EXTENSIONS}
    CACHE INTERNAL ""
    )

  set(LATEX_PDF_VECTOR_IMAGE_EXTENSIONS .pdf CACHE INTERNAL "")
  set(LATEX_PDF_RASTER_IMAGE_EXTENSIONS .jpeg .jpg .png CACHE INTERNAL "")
  set(LATEX_PDF_IMAGE_EXTENSIONS
    ${LATEX_PDF_VECTOR_IMAGE_EXTENSIONS}
    ${LATEX_PDF_RASTER_IMAGE_EXTENSIONS}
    CACHE INTERNAL ""
    )

  set(LATEX_OTHER_VECTOR_IMAGE_EXTENSIONS .ai .dot .svg CACHE INTERNAL "")
  set(LATEX_OTHER_RASTER_IMAGE_EXTENSIONS
    .bmp .bmp2 .bmp3 .dcm .dcx .ico .gif .pict .ppm .tif .tiff
    CACHE INTERNAL "")
  set(LATEX_OTHER_IMAGE_EXTENSIONS
    ${LATEX_OTHER_VECTOR_IMAGE_EXTENSIONS}
    ${LATEX_OTHER_RASTER_IMAGE_EXTENSIONS}
    CACHE INTERNAL ""
    )

  set(LATEX_VECTOR_IMAGE_EXTENSIONS
    ${LATEX_DVI_VECTOR_IMAGE_EXTENSIONS}
    ${LATEX_PDF_VECTOR_IMAGE_EXTENSIONS}
    ${LATEX_OTHER_VECTOR_IMAGE_EXTENSIONS}
    CACHE INTERNAL ""
    )
  set(LATEX_RASTER_IMAGE_EXTENSIONS
    ${LATEX_DVI_RASTER_IMAGE_EXTENSIONS}
    ${LATEX_PDF_RASTER_IMAGE_EXTENSIONS}
    ${LATEX_OTHER_RASTER_IMAGE_EXTENSIONS}
    CACHE INTERNAL ""
    )
  set(LATEX_IMAGE_EXTENSIONS
    ${LATEX_DVI_IMAGE_EXTENSIONS}
    ${LATEX_PDF_IMAGE_EXTENSIONS}
    ${LATEX_OTHER_IMAGE_EXTENSIONS}
    CACHE INTERNAL ""
    )
endfunction(latex_setup_variables)

function(latex_setup_targets)
  if(NOT TARGET pdf)
    add_custom_target(pdf)
  endif()
  if(NOT TARGET dvi)
    add_custom_target(dvi)
  endif()
  if(NOT TARGET ps)
    add_custom_target(ps)
  endif()
  if(NOT TARGET safepdf)
    add_custom_target(safepdf)
  endif()
  if(NOT TARGET html)
    add_custom_target(html)
  endif()
  if(NOT TARGET auxclean)
    add_custom_target(auxclean)
  endif()
endfunction(latex_setup_targets)

function(latex_get_output_path var)
  set(latex_output_path)
  if(LATEX_OUTPUT_PATH)
    get_filename_component(
      LATEX_OUTPUT_PATH_FULL "${LATEX_OUTPUT_PATH}" ABSOLUTE
      )
    if("${LATEX_OUTPUT_PATH_FULL}" STREQUAL "${CMAKE_CURRENT_SOURCE_DIR}")
      message(SEND_ERROR "You cannot set LATEX_OUTPUT_PATH to the same directory that contains LaTeX input files.")
    else()
      set(latex_output_path "${LATEX_OUTPUT_PATH_FULL}")
    endif()
  else()
    if("${CMAKE_CURRENT_BINARY_DIR}" STREQUAL "${CMAKE_CURRENT_SOURCE_DIR}")
      message(SEND_ERROR "LaTeX files must be built out of source or you must set LATEX_OUTPUT_PATH.")
    else()
      set(latex_output_path "${CMAKE_CURRENT_BINARY_DIR}")
    endif()
  endif()
  set(${var} ${latex_output_path} PARENT_SCOPE)
endfunction(latex_get_output_path)

function(latex_add_convert_command
    output_path
    input_path
    output_extension
    input_extension
    flags
    )
  set(require_imagemagick_convert TRUE)
  set(convert_flags "")
  if(${input_extension} STREQUAL ".eps" AND ${output_extension} STREQUAL ".pdf")
    # ImageMagick has broken eps to pdf conversion
    # use ps2pdf instead
    if(PS2PDF_CONVERTER)
      set(require_imagemagick_convert FALSE)
      set(converter ${PS2PDF_CONVERTER})
      set(convert_flags -dEPSCrop ${PS2PDF_CONVERTER_ARGS})
    else()
      message(SEND_ERROR "Using postscript files with pdflatex requires ps2pdf for conversion.")
    endif()
  elseif(${input_extension} STREQUAL ".pdf" AND ${output_extension} STREQUAL ".eps")
    # ImageMagick can also be sketchy on pdf to eps conversion.  Not good with
    # color spaces and tends to unnecessarily rasterize.
    # use pdftops instead
    if(PDFTOPS_CONVERTER)
      set(require_imagemagick_convert FALSE)
      set(converter ${PDFTOPS_CONVERTER})
      set(convert_flags -eps ${PDFTOPS_CONVERTER_ARGS})
    else()
      message(STATUS "Consider getting pdftops from Poppler to convert PDF images to EPS images.")
      set(convert_flags ${flags})
    endif()
  elseif(${input_extension} STREQUAL ".svg" AND ${output_extension} STREQUAL ".pdf")
    # Convert SVG with Inkscape
    get_filename_component(output_dir "${output_path}" DIRECTORY)
    get_filename_component(output_name "${output_path}" NAME)
    get_filename_component(input_namewle "${input_path}" NAME_WLE)

    add_custom_command(OUTPUT ${output_path}
      COMMAND /usr/bin/inkscape
      ARGS --export-area-page --export-dpi=600 --export-text-to-path --export-filename="${output_name}" "${input_path}"
      WORKING_DIRECTORY ${output_dir}
      DEPENDS ${input_path}
    )
  else()
    set(convert_flags ${flags})
  endif()

  if(require_imagemagick_convert)
    if(IMAGEMAGICK_CONVERT)
      string(TOLOWER ${IMAGEMAGICK_CONVERT} IMAGEMAGICK_CONVERT_LOWERCASE)
      if(${IMAGEMAGICK_CONVERT_LOWERCASE} MATCHES "system32[/\\\\]convert\\.exe")
        message(SEND_ERROR "IMAGEMAGICK_CONVERT set to Window's convert.exe for changing file systems rather than ImageMagick's convert for changing image formats. Please make sure ImageMagick is installed (available at http://www.imagemagick.org). If you have a recent version of ImageMagick (7.0 or higher), use the magick program instead of convert for IMAGEMAGICK_CONVERT.")
      else()
        set(converter ${IMAGEMAGICK_CONVERT})
        # ImageMagick requires a special order of arguments where resize and
        # arguments of that nature must be placed after the input image path.
        add_custom_command(OUTPUT ${output_path}
          COMMAND ${converter}
            ARGS ${input_path} ${convert_flags} ${output_path}
          DEPENDS ${input_path}
          )
      endif()
    else()
      message(SEND_ERROR "Could not find convert program. Please download ImageMagick from http://www.imagemagick.org and install.")
    endif()
  else() # Not ImageMagick convert
    add_custom_command(OUTPUT ${output_path}
      COMMAND ${converter}
        ARGS ${convert_flags} ${input_path} ${output_path}
      DEPENDS ${input_path}
      )
  endif()
endfunction(latex_add_convert_command)

# Makes custom commands to convert a file to a particular type.
function(latex_convert_image
    output_files_var
    input_file
    output_extension
    convert_flags
    output_extensions
    other_files
    )
  set(output_file_list)
  set(input_dir ${CMAKE_CURRENT_SOURCE_DIR})
  latex_get_output_path(output_dir)

  latex_get_filename_component(extension "${input_file}" EXT)

  # Check input filename for potential problems with LaTeX.
  latex_get_filename_component(name "${input_file}" NAME_WE)
  set(suggested_name "${name}")
  if(suggested_name MATCHES ".*\\..*")
    string(REPLACE "." "-" suggested_name "${suggested_name}")
  endif()
  if(suggested_name MATCHES ".* .*")
    string(REPLACE " " "-" suggested_name "${suggested_name}")
  endif()
  if(NOT suggested_name STREQUAL name)
    message(WARNING "Some LaTeX distributions have problems with image file names with multiple extensions or spaces. Consider changing ${name}${extension} to something like ${suggested_name}${extension}.")
  endif()

  string(REGEX REPLACE "\\.[^.]*\$" ${output_extension} output_file
    "${input_file}")

  latex_list_contains(is_type ${extension} ${output_extensions})
  if(is_type)
    if(convert_flags)
      latex_add_convert_command(${output_dir}/${output_file}
        ${input_dir}/${input_file} ${output_extension} ${extension}
        "${convert_flags}")
      set(output_file_list ${output_dir}/${output_file})
    else()
      # As a shortcut, we can just copy the file.
      add_custom_command(OUTPUT ${output_dir}/${input_file}
        COMMAND ${CMAKE_COMMAND}
        ARGS -E copy ${input_dir}/${input_file} ${output_dir}/${input_file}
        DEPENDS ${input_dir}/${input_file}
        )
      set(output_file_list ${output_dir}/${input_file})
    endif()
  else()
    set(do_convert TRUE)
    # Check to see if there is another input file of the appropriate type.
    foreach(valid_extension ${output_extensions})
      string(REGEX REPLACE "\\.[^.]*\$" ${output_extension} try_file
        "${input_file}")
      latex_list_contains(has_native_file "${try_file}" ${other_files})
      if(has_native_file)
        set(do_convert FALSE)
      endif()
    endforeach(valid_extension)

    # If we still need to convert, do it.
    if(do_convert)
      latex_add_convert_command(${output_dir}/${output_file}
        ${input_dir}/${input_file} ${output_extension} ${extension}
        "${convert_flags}")
      set(output_file_list ${output_dir}/${output_file})
    endif()
  endif()

  set(${output_files_var} ${output_file_list} PARENT_SCOPE)
endfunction(latex_convert_image)

# Adds custom commands to process the given files for dvi and pdf builds.
# Adds the output files to the given variables (does not replace).
function(latex_process_images dvi_outputs_var pdf_outputs_var)
  latex_get_output_path(output_dir)
  set(dvi_outputs)
  set(pdf_outputs)
  foreach(file ${ARGN})
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${file}")
      latex_get_filename_component(extension "${file}" EXT)
      set(convert_flags)

      # Check to see if we need to downsample the image.
      latex_list_contains(is_raster "${extension}"
        ${LATEX_RASTER_IMAGE_EXTENSIONS})
      if(LATEX_SMALL_IMAGES)
        if(is_raster)
          set(convert_flags -resize ${LATEX_RASTER_SCALE}%)
        endif()
      endif()

      # Make sure the output directory exists.
      latex_get_filename_component(path "${output_dir}/${file}" PATH)
      make_directory("${path}")

      # Do conversions for dvi.
      if(NOT LATEX_FORCE_PDF)
          latex_convert_image(output_files "${file}" .eps "${convert_flags}"
            "${LATEX_DVI_IMAGE_EXTENSIONS}" "${ARGN}")
          list(APPEND dvi_outputs ${output_files})
      endif ()

      # Do conversions for pdf.
      if(NOT LATEX_FORCE_DVI AND NOT LATEX_FORCE_HTML)
        if(is_raster)
          latex_convert_image(output_files "${file}" .png "${convert_flags}"
            "${LATEX_PDF_IMAGE_EXTENSIONS}" "${ARGN}")
          list(APPEND pdf_outputs ${output_files})
        else()
          latex_convert_image(output_files "${file}" .pdf "${convert_flags}"
            "${LATEX_PDF_IMAGE_EXTENSIONS}" "${ARGN}")
          list(APPEND pdf_outputs ${output_files})
        endif()
      endif()
    else()
      message(WARNING "Could not find file ${CMAKE_CURRENT_SOURCE_DIR}/${file}.  Are you sure you gave relative paths to IMAGES?")
    endif()
  endforeach(file)

  set(${dvi_outputs_var} ${dvi_outputs} PARENT_SCOPE)
  set(${pdf_outputs_var} ${pdf_outputs} PARENT_SCOPE)
endfunction(latex_process_images)

function(latex_copy_globbed_files pattern dest)
  if(${CMAKE_VERSION} VERSION_LESS "3.12")
    file(GLOB file_list ${pattern})
  else()
    file(GLOB file_list CONFIGURE_DEPENDS ${pattern})
  endif()
  foreach(in_file ${file_list})
    latex_get_filename_component(out_file ${in_file} NAME)
    configure_file(${in_file} ${dest}/${out_file} COPYONLY)
  endforeach(in_file)
endfunction(latex_copy_globbed_files)

function(latex_copy_input_file file)
  latex_get_output_path(output_dir)

  if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${file})
    latex_get_filename_component(path ${file} PATH)
    file(MAKE_DIRECTORY ${output_dir}/${path})

    latex_list_contains(use_config ${file} ${LATEX_CONFIGURE})
    if(use_config)
      configure_file(${CMAKE_CURRENT_SOURCE_DIR}/${file}
        ${output_dir}/${file}
        @ONLY
        )
      add_custom_command(OUTPUT ${output_dir}/${file}
        COMMAND ${CMAKE_COMMAND}
        ARGS ${CMAKE_BINARY_DIR}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${file}
        )
    else()
      add_custom_command(OUTPUT ${output_dir}/${file}
        COMMAND ${CMAKE_COMMAND}
        ARGS -E copy ${CMAKE_CURRENT_SOURCE_DIR}/${file} ${output_dir}/${file}
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${file}
        )
    endif()
  else()
    if(EXISTS ${output_dir}/${file})
      # Special case: output exists but input does not.  Assume that it was
      # created elsewhere and skip the input file copy.
    else()
      message("Could not find input file ${CMAKE_CURRENT_SOURCE_DIR}/${file}")
    endif()
  endif()
endfunction(latex_copy_input_file)

function(process_markup_file filevar)
  # Notes
  # - Reconfiration is triggered when Markdown changes. This is to allow for image list to be determined from that file.
  #
  # Stuff to improve:
  # - Don't hardcode media folder
  # - Clear media folder first?
  # set(make_pdf_depends " ")
  get_filename_component(file_ext "${${filevar}}" EXT)
  string(TOLOWER "${file_ext}" file_ext)

  if(file_ext STREQUAL ".md")
    message(STATUS " Processing markdown file: ${${filevar}} ")
  else()
    return()
  endif()

  set(input_name "${${filevar}}")

  # "${type}" STREQUAL ".tex"

  # Process Obsidian notes first, to check for external images
  # execute_process(COMMAND cmake -E make_directory ${CMAKE_SOURCE_DIR}/media)
  # list(APPEND LATEX_IMAGE_DIRS media)
  set(image_characters "- A-Z:ÆØÅa-zæøå_0-9\\.")

  file(READ ${input_name} i)

  # Square brackets are tricky in regex. Replace them.
  string(REPLACE "[" "<" i "${i}")
  string(REPLACE "]" ">" i "${i}")
  string(REPLACE "\\|" "|" i "${i}")

  # message(${i})

  # message(FATAL_ERROR " ")

  # # Copy and rename images
  # string(REGEX MATCHALL " <[^]*[^>]*> " image_matches ${i})
  # foreach(image_match ${image_matches})
  # # It was tricky to remove trailing whitespaces when the bar was escaped. Fixed by first matching until extension punctuation.
  # string(REGEX MATCH " <([^\\.]*[^ |]*) " image_name ${image_match})

  # # Remove spaces
  # string(REPLACE " " " _" new_image_name "${image_name} ")
  # string(REPLACE " ${image_name}" "${new_image_name}" i "${i} ")

  # # Copy files
  # get_filename_component(dir ${input_name} DIRECTORY)
  # configure_file(" ${dir}/media/${image_name}" "media/${new_image_name} " COPYONLY)
  # endforeach()

  # Copy all wikilink images to media folder
  # message(" string(REGEX MATCHALL "\\!\\[\\[[${image_characters}\\|]*\\]\\]" image_matches ${i}) ")
  string(REGEX MATCHALL "<<[^\\.]*[^>]*>>" image_matches ${i})

  foreach(image_match ${image_matches})
    # message("image_match: ${image_match}")

    # It was tricky to remove trailing whitespaces when the bar was escaped. Fixed by first matching until extension punctuation.
    string(REGEX REPLACE "<<([^\\.]*[^ |]*).*" "\\1" image_name "${image_match}")

    # set(image_name ${CMAKE_MATCH_1})

    # message("image_name: ${image_name}")
    message("image_name: ${image_name}")

    # Remove spaces
    string(REPLACE " " "-" new_image_name "${image_name}")
    string(REPLACE "%20" "-" new_image_name "${new_image_name}")
    string(REPLACE "_" "-" new_image_name "${new_image_name}")
    string(REPLACE "${image_name}" "${new_image_name}" i "${i}")

    message("new_image_name: ${new_image_name}")

    string(REGEX REPLACE "[^\\.]\\." "" ext "${new_image_name}")
    get_filename_component(dir ${input_name} DIRECTORY)

    if(ext MATCHES "png|jpg|jpeg")
      message("configure_file(${dir}/media/${image_name} ${CMAKE_BINARY_DIR}/media/${new_image_name} COPYONLY)")
      configure_file("${dir}/media/${image_name}" "${CMAKE_BINARY_DIR}/media/${new_image_name}" COPYONLY)
    endif()
  endforeach()

  message("======Markdown")

  # Repeat for Markdown links
  string(REGEX MATCHALL "<[^>]*>\([^\)]*\)" image_matches ${i})

  foreach(image_match ${image_matches})
    # message("image_match: ${image_match}")

    # It was tricky to remove trailing whitespaces when the bar was escaped. Fixed by first matching until extension punctuation.
    string(REGEX MATCH ">\\(([^\\.]*[^ |]*)" m_ "${image_match}")
    set(image_link_name ${CMAKE_MATCH_1})

    # message("image_name: ${image_name}")
    message("image_link_name: ${image_link_name}")

    # Remove spaces
    string(REPLACE "%20" " " image_name "${image_link_name}")
    string(REPLACE " " "-" new_image_name "${image_name}")
    string(REPLACE "_" "-" new_image_name "${new_image_name}")
    string(REPLACE "${image_link_name}" "${new_image_name}" i "${i}")

    message("new_image_name: ${new_image_name}")

    string(REGEX REPLACE "[^\\.]\\." "" ext "${new_image_name}")
    get_filename_component(dir ${input_name} DIRECTORY)

    if(ext MATCHES "png|jpg|jpeg")
      message("configure_file(${dir}/media/${image_name} ${CMAKE_BINARY_DIR}/media/${new_image_name} COPYONLY)")
      configure_file("${dir}/media/${image_name}" "${CMAKE_BINARY_DIR}/media/${new_image_name}" COPYONLY)
    endif()
  endforeach()

  # string(REGEX REPLACE "\\!\\[\\[([${image_characters}]*)\\|*([0-9]*)" "" image_match "${image_match}")

  # Remove spaces
  # string(REPLACE " " "_" new_image_name "${image_name}")

  # Convert to Markdown links
  string(REGEX REPLACE "<<([^\\.]*[^ |]*)([ |0-9x]*)([^>]*)>>" "[\\3](\\1)" i ${i})
  string(REPLACE "<" "[" i "${i}")
  string(REPLACE ">" "]" i "${i}")

  # cmake_path()
  get_filename_component(out_name ${input_name} NAME)

  # set(outname "${out_name}.tex")
  # message("file(WRITE \"${out_name}\" \"${i}\")")
  file(WRITE ${CMAKE_BINARY_DIR}/${out_name} "${i}")

  # https://stackoverflow.com/questions/25482822/add-dependency-to-the-cmake-generated-build-system-itself
  set_property(
    DIRECTORY
    APPEND
    PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${input_name}"
  )

  # message("
  #   add_custom_command(
  #   OUTPUT ${out_name}.tex
  #   COMMAND pandoc ARGS --template=template/pandoc.template ${CMAKE_BINARY_DIR}/${out_name} -o ${CMAKE_SOURCE_DIR}/${out_name}.tex
  #   BYPRODUCTS ${out_name}.tex
  #   DEPENDS ${input_name}
  #   VERBATIM
  # )
  # ")

  add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${out_name}.tex
    COMMAND pandoc ARGS --template=template/pandoc.template ${CMAKE_BINARY_DIR}/${out_name} -o ${CMAKE_CURRENT_BINARY_DIR}/${out_name}.tex
    # BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/${out_name}.tex
    DEPENDS ${input_name}
    VERBATIM
  )

  set(${filevar} ${CMAKE_BINARY_DIR}/${out_name}.tex PARENT_SCOPE)

  # message(FATAL_ERROR "")
  # --template=default.latex
  # set(make_pdf_depends ${out_name}.tex.stamp)

  # list(APPEND LATEX_INPUTS ${CMAKE_SOURCE_DIR}/${out_name}.tex)
endfunction()

#############################################################################
# Commands provided by the UseLATEX.cmake "package"
#############################################################################

function(latex_usage command message)
  message(SEND_ERROR
      "${message}\n  Usage: ${command}(<tex_file>\n           [BIBFILES <bib_file> <bib_file> ...]\n           [INPUTS <tex_file> <tex_file> ...]\n           [IMAGE_DIRS <directory1> <directory2> ...]\n           [IMAGES <image_file1> <image_file2>\n           [CONFIGURE <tex_file> <tex_file> ...]\n           [DEPENDS <tex_file> <tex_file> ...]\n           [MULTIBIB_NEWCITES] <suffix_list>\n           [USE_BIBLATEX] [USE_INDEX] [USE_GLOSSARY] [USE_NOMENCL]\n           [FORCE_PDF] [FORCE_DVI] [FORCE_HTML]\n           [TARGET_NAME] <name>\n           [EXCLUDE_FROM_ALL]\n           [EXCLUDE_FROM_DEFAULTS])"
    )
endfunction(latex_usage command message)

# Parses arguments to add_latex_document and ADD_LATEX_TARGETS and sets the
# variables LATEX_TARGET, LATEX_IMAGE_DIR, LATEX_BIBFILES, LATEX_DEPENDS, and
# LATEX_INPUTS.
function(parse_add_latex_arguments command latex_main_input)
  set(options
    USE_BIBLATEX
    USE_INDEX
    USE_GLOSSARY
    USE_NOMENCL
    FORCE_PDF
    FORCE_DVI
    FORCE_HTML
    EXCLUDE_FROM_ALL
    EXCLUDE_FROM_DEFAULTS
    # Deprecated options
    USE_GLOSSARIES
    DEFAULT_PDF
    DEFAULT_SAFEPDF
    DEFAULT_PS
    NO_DEFAULT
    MANGLE_TARGET_NAMES
    )
  set(oneValueArgs
    TARGET_NAME
    )
  set(multiValueArgs
    BIBFILES
    MULTIBIB_NEWCITES
    INPUTS
    IMAGE_DIRS
    IMAGES
    CONFIGURE
    DEPENDS
    INDEX_NAMES
    INCLUDE_DIRECTORIES
    )
  cmake_parse_arguments(
    LATEX "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  # Handle invalid and deprecated arguments
  if(LATEX_UNPARSED_ARGUMENTS)
    latex_usage(${command} "Invalid or deprecated arguments: ${LATEX_UNPARSED_ARGUMENTS}")
  endif()
  if(LATEX_USE_GLOSSARIES)
    latex_usage(${command} "USE_GLOSSARIES option removed in version 1.6.1. Use USE_GLOSSARY instead.")
  endif()
  if(LATEX_DEFAULT_PDF)
    latex_usage(${command} "DEFAULT_PDF option removed in version 2.0. Use FORCE_PDF option or LATEX_DEFAULT_BUILD CMake variable instead.")
  endif()
  if(LATEX_DEFAULT_SAFEPDF)
    latex_usage(${command} "DEFAULT_SAFEPDF option removed in version 2.0. Use LATEX_DEFAULT_BUILD CMake variable instead.")
  endif()
  if(LATEX_DEFAULT_DVI)
    latex_usage(${command} "DEFAULT_DVI option removed in version 2.0. Use FORCE_DVI option or LATEX_DEFAULT_BUILD CMake variable instead.")
  endif()
  if(LATEX_NO_DEFAULT)
    latex_usage(${command} "NO_DEFAULT option removed in version 2.0. Use EXCLUDE_FROM_ALL instead.")
  endif()
  if(LATEX_MANGLE_TARGET_NAMES)
    latex_usage(${command} "MANGLE_TARGET_NAMES option removed in version 2.0. All LaTeX targets use mangled names now.")
  endif()

  # Capture the first argument, which is the main LaTeX input.
  latex_get_filename_component(latex_target ${latex_main_input} NAME_WE)
  set(LATEX_MAIN_INPUT ${latex_main_input} PARENT_SCOPE)
  set(LATEX_TARGET ${latex_target} PARENT_SCOPE)

  # Propagate the result variables to the caller
  foreach(arg_name ${options} ${oneValueArgs} ${multiValueArgs})
    set(var_name LATEX_${arg_name})
    set(${var_name} ${${var_name}} PARENT_SCOPE)
  endforeach(arg_name)
endfunction(parse_add_latex_arguments)

function(add_latex_targets_internal)
  latex_get_output_path(output_dir)

  if(LATEX_USE_SYNCTEX)
    set(synctex_flags ${LATEX_SYNCTEX_ARGS})
  else()
    set(synctex_flags)
  endif()

  # The commands to run LaTeX.  They are repeated multiple times.
  set(latex_build_command
    ${LATEX_COMPILER} ${LATEX_COMPILER_ARGS} ${synctex_flags} ${LATEX_MAIN_INPUT}
    )
  if(LATEX_COMPILER_ARGS MATCHES ".*batchmode.*")
    # Wrap command in script that dumps the log file on error. This makes sure
    # errors can be seen.
    set(latex_build_command
      ${CMAKE_COMMAND}
        -D LATEX_BUILD_COMMAND=execute_latex
        -D LATEX_WORKING_DIRECTORY="${output_dir}"
        -D LATEX_FULL_COMMAND="${latex_build_command}"
        -D LATEX_OUTPUT_FILE="${LATEX_TARGET}.dvi"
        -D LATEX_LOG_FILE="${LATEX_TARGET}.log"
        -P "${LATEX_USE_LATEX_LOCATION}"
      )
  endif()
  set(pdflatex_build_command
    ${PDFLATEX_COMPILER} ${PDFLATEX_COMPILER_ARGS} ${synctex_flags} ${LATEX_MAIN_INPUT}
    )
  if(PDFLATEX_COMPILER_ARGS MATCHES ".*batchmode.*")
    # Wrap command in script that dumps the log file on error. This makes sure
    # errors can be seen.
    set(pdflatex_build_command
      ${CMAKE_COMMAND}
        -D LATEX_BUILD_COMMAND=execute_latex
        -D LATEX_WORKING_DIRECTORY="${output_dir}"
        -D LATEX_FULL_COMMAND="${pdflatex_build_command}"
        -D LATEX_OUTPUT_FILE="${LATEX_TARGET}.pdf"
        -D LATEX_LOG_FILE="${LATEX_TARGET}.log"
        -P "${LATEX_USE_LATEX_LOCATION}"
      )
  endif()

  if(LATEX_INCLUDE_DIRECTORIES)
    # The include directories needs to start with the build directory so
    # that the copied files can be found. It also needs to end with an
    # empty directory so that the standard system directories are included
    # after any specified.
    set(LATEX_INCLUDE_DIRECTORIES . ${LATEX_INCLUDE_DIRECTORIES} "")

    # CMake separates items in a list with a semicolon. Lists of
    # directories on most systems are separated by colons, so we can do a
    # simple text replace. On Windows, directories are separated by
    # semicolons, but we replace them with the $<SEMICOLON> generator
    # expression to make sure CMake treats it as a single string.
    if(CMAKE_HOST_WIN32)
      string(REPLACE ";" "$<SEMICOLON>" TEXINPUTS "${LATEX_INCLUDE_DIRECTORIES}")
    else()
      string(REPLACE ";" ":" TEXINPUTS "${LATEX_INCLUDE_DIRECTORIES}")
    endif()

    # Set the TEXINPUTS environment variable
    set(latex_build_command
      ${CMAKE_COMMAND} -E env TEXINPUTS=${TEXINPUTS} ${latex_build_command})
    set(pdflatex_build_command
      ${CMAKE_COMMAND} -E env TEXINPUTS=${TEXINPUTS} ${pdflatex_build_command})
  endif()

  if(NOT LATEX_TARGET_NAME)
    # Use the main filename (minus the .tex) as the target name. Remove any
    # spaces since CMake cannot have spaces in its target names.
    string(REPLACE " " "_" LATEX_TARGET_NAME ${LATEX_TARGET})
  endif()

  # Some LaTeX commands may need to be modified (or may not work) if the main
  # tex file is in a subdirectory. Make a flag for that.
  get_filename_component(LATEX_MAIN_INPUT_SUBDIR ${LATEX_MAIN_INPUT} DIRECTORY)

  # Set up target names.
  set(dvi_target      ${LATEX_TARGET_NAME}_dvi)
  set(pdf_target      ${LATEX_TARGET_NAME}_pdf)
  set(ps_target       ${LATEX_TARGET_NAME}_ps)
  set(safepdf_target  ${LATEX_TARGET_NAME}_safepdf)
  set(html_target     ${LATEX_TARGET_NAME}_html)
  set(auxclean_target ${LATEX_TARGET_NAME}_auxclean)

  # Probably not all of these will be generated, but they could be.
  # Note that the aux file is added later.
  set(auxiliary_clean_files
    ${output_dir}/${LATEX_TARGET}.aux
    ${output_dir}/${LATEX_TARGET}.bbl
    ${output_dir}/${LATEX_TARGET}.blg
    ${output_dir}/${LATEX_TARGET}-blx.bib
    ${output_dir}/${LATEX_TARGET}.glg
    ${output_dir}/${LATEX_TARGET}.glo
    ${output_dir}/${LATEX_TARGET}.gls
    ${output_dir}/${LATEX_TARGET}.idx
    ${output_dir}/${LATEX_TARGET}.ilg
    ${output_dir}/${LATEX_TARGET}.ind
    ${output_dir}/${LATEX_TARGET}.ist
    ${output_dir}/${LATEX_TARGET}.log
    ${output_dir}/${LATEX_TARGET}.out
    ${output_dir}/${LATEX_TARGET}.toc
    ${output_dir}/${LATEX_TARGET}.lof
    ${output_dir}/${LATEX_TARGET}.xdy
    ${output_dir}/${LATEX_TARGET}.synctex.gz
    ${output_dir}/${LATEX_TARGET}.synctex.bak.gz
    ${output_dir}/${LATEX_TARGET}.dvi
    ${output_dir}/${LATEX_TARGET}.ps
    ${output_dir}/${LATEX_TARGET}.pdf
    )

  set(image_list ${LATEX_IMAGES})

  # For each directory in LATEX_IMAGE_DIRS, glob all the image files and
  # place them in LATEX_IMAGES.
  foreach(dir ${LATEX_IMAGE_DIRS})
    if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${dir})
      message(WARNING "Image directory ${CMAKE_CURRENT_SOURCE_DIR}/${dir} does not exist.  Are you sure you gave relative directories to IMAGE_DIRS?")
    endif()
    foreach(extension ${LATEX_IMAGE_EXTENSIONS})
      if(${CMAKE_VERSION} VERSION_LESS "3.12")
        file(GLOB files ${CMAKE_CURRENT_SOURCE_DIR}/${dir}/*${extension})
      else()
        file(GLOB files CONFIGURE_DEPENDS
          ${CMAKE_CURRENT_SOURCE_DIR}/${dir}/*${extension}
          )
      endif()
      foreach(file ${files})
        latex_get_filename_component(filename ${file} NAME)
        list(APPEND image_list ${dir}/${filename})
      endforeach(file)
    endforeach(extension)
  endforeach(dir)

  latex_process_images(dvi_images pdf_images ${image_list})

  set(make_dvi_command
    ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${latex_build_command})
  set(make_pdf_command
    ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${pdflatex_build_command}
    )

  set(make_dvi_depends ${LATEX_DEPENDS} ${dvi_images})
  set(make_pdf_depends ${LATEX_DEPENDS} ${pdf_images})
  foreach(input ${LATEX_MAIN_INPUT} ${LATEX_INPUTS})
    list(APPEND make_dvi_depends ${output_dir}/${input})
    list(APPEND make_pdf_depends ${output_dir}/${input})
    if(${input} MATCHES "\\.tex$")
      # Dependent .tex files might have their own .aux files created.  Make
      # sure these get cleaned as well.  This might replicate the cleaning
      # of the main .aux file, which is OK.
      string(REGEX REPLACE "\\.tex$" "" input_we ${input})
      list(APPEND auxiliary_clean_files
        ${output_dir}/${input_we}.aux
        ${output_dir}/${input}.aux
        )
    endif()
  endforeach(input)

  set(all_latex_sources ${LATEX_MAIN_INPUT} ${LATEX_INPUTS} ${image_list})

  if(LATEX_USE_GLOSSARY)
    foreach(dummy 0 1)   # Repeat these commands twice.
      set(make_dvi_command ${make_dvi_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${CMAKE_COMMAND}
        -D LATEX_BUILD_COMMAND=makeglossaries
        -D LATEX_TARGET=${LATEX_TARGET}
        -D MAKEINDEX_COMPILER=${MAKEINDEX_COMPILER}
        -D XINDY_COMPILER=${XINDY_COMPILER}
        -D MAKEGLOSSARIES_COMPILER_ARGS=${MAKEGLOSSARIES_COMPILER_ARGS}
        -P ${LATEX_USE_LATEX_LOCATION}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${latex_build_command}
        )
      set(make_pdf_command ${make_pdf_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${CMAKE_COMMAND}
        -D LATEX_BUILD_COMMAND=makeglossaries
        -D LATEX_TARGET=${LATEX_TARGET}
        -D MAKEINDEX_COMPILER=${MAKEINDEX_COMPILER}
        -D XINDY_COMPILER=${XINDY_COMPILER}
        -D MAKEGLOSSARIES_COMPILER_ARGS=${MAKEGLOSSARIES_COMPILER_ARGS}
        -P ${LATEX_USE_LATEX_LOCATION}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${pdflatex_build_command}
        )
    endforeach(dummy)
  endif()

  if(LATEX_USE_NOMENCL)
    foreach(dummy 0 1)   # Repeat these commands twice.
      set(make_dvi_command ${make_dvi_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${CMAKE_COMMAND}
        -D LATEX_BUILD_COMMAND=makenomenclature
        -D LATEX_TARGET=${LATEX_TARGET}
        -D MAKEINDEX_COMPILER=${MAKEINDEX_COMPILER}
        -D MAKENOMENCLATURE_COMPILER_ARGS=${MAKENOMENCLATURE_COMPILER_ARGS}
        -P ${LATEX_USE_LATEX_LOCATION}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${latex_build_command}
        )
      set(make_pdf_command ${make_pdf_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${CMAKE_COMMAND}
        -D LATEX_BUILD_COMMAND=makenomenclature
        -D LATEX_TARGET=${LATEX_TARGET}
        -D MAKEINDEX_COMPILER=${MAKEINDEX_COMPILER}
        -D MAKENOMENCLATURE_COMPILER_ARGS=${MAKENOMENCLATURE_COMPILER_ARGS}
        -P ${LATEX_USE_LATEX_LOCATION}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${pdflatex_build_command}
        )
    endforeach(dummy)
  endif()

  if(LATEX_BIBFILES)
    set(suppress_bib_output)
    if(LATEX_USE_BIBLATEX)
      if(NOT BIBER_COMPILER)
        message(SEND_ERROR "I need the biber command.")
      endif()
      set(bib_compiler ${BIBER_COMPILER})
      set(bib_compiler_flags ${BIBER_COMPILER_ARGS})

      if(NOT BIBER_COMPILER_ARGS MATCHES ".*-q.*")
        # Only suppress bib output if the quiet option is not specified.
        set(suppress_bib_output TRUE)
      endif()

      if(LATEX_USE_BIBLATEX_CONFIG)
        list(APPEND auxiliary_clean_files ${output_dir}/biblatex.cfg)
        list(APPEND make_dvi_depends ${output_dir}/biblatex.cfg)
        list(APPEND make_pdf_depends ${output_dir}/biblatex.cfg)
      endif()
    else()
      set(bib_compiler ${BIBTEX_COMPILER})
      set(bib_compiler_flags ${BIBTEX_COMPILER_ARGS})
    endif()
    if(LATEX_MULTIBIB_NEWCITES)
      # Suppressed bib output currently not supported for multibib
      foreach (multibib_auxfile ${LATEX_MULTIBIB_NEWCITES})
        latex_get_filename_component(multibib_target ${multibib_auxfile} NAME_WE)
        set(make_dvi_command ${make_dvi_command}
          COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
          ${bib_compiler} ${bib_compiler_flags} ${multibib_target})
        set(make_pdf_command ${make_pdf_command}
          COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
          ${bib_compiler} ${bib_compiler_flags} ${multibib_target})
        set(auxiliary_clean_files ${auxiliary_clean_files}
          ${output_dir}/${multibib_target}.aux)
      endforeach (multibib_auxfile ${LATEX_MULTIBIB_NEWCITES})
    else()
      set(full_bib_command
        ${bib_compiler} ${bib_compiler_flags} ${LATEX_TARGET})
      if(suppress_bib_output)
        set(full_bib_command
          ${CMAKE_COMMAND}
          -D LATEX_BUILD_COMMAND=execute_latex
          -D LATEX_WORKING_DIRECTORY="${output_dir}"
          -D LATEX_FULL_COMMAND="${full_bib_command}"
          -D LATEX_OUTPUT_FILE="${LATEX_TARGET}.bbl"
          -D LATEX_LOG_FILE="${LATEX_TARGET}.blg"
          -P "${LATEX_USE_LATEX_LOCATION}"
          )
      endif()
      set(make_dvi_command ${make_dvi_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${full_bib_command})
      set(make_pdf_command ${make_pdf_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${full_bib_command})
    endif()

    foreach (bibfile ${LATEX_BIBFILES})
      list(APPEND make_dvi_depends ${output_dir}/${bibfile})
      list(APPEND make_pdf_depends ${output_dir}/${bibfile})
    endforeach (bibfile ${LATEX_BIBFILES})
  else()
    if(LATEX_MULTIBIB_NEWCITES)
      message(WARNING "MULTIBIB_NEWCITES has no effect without BIBFILES option.")
    endif()
  endif()

  if(LATEX_USE_INDEX)
    if(LATEX_INDEX_NAMES)
      set(INDEX_NAMES ${LATEX_INDEX_NAMES})
    else()
      set(INDEX_NAMES ${LATEX_TARGET})
    endif()
    foreach(idx_name ${INDEX_NAMES})
      set(make_dvi_command ${make_dvi_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${latex_build_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${MAKEINDEX_COMPILER} ${MAKEINDEX_COMPILER_ARGS} ${idx_name}.idx)
      set(make_pdf_command ${make_pdf_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${pdflatex_build_command}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${MAKEINDEX_COMPILER} ${MAKEINDEX_COMPILER_ARGS} ${idx_name}.idx)
      set(auxiliary_clean_files ${auxiliary_clean_files}
        ${output_dir}/${idx_name}.idx
        ${output_dir}/${idx_name}.ilg
        ${output_dir}/${idx_name}.ind)
    endforeach()
  else()
    if(LATEX_INDEX_NAMES)
      message(WARNING "INDEX_NAMES has no effect without USE_INDEX option.")
    endif()
  endif()

  set(make_dvi_command ${make_dvi_command}
    COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${latex_build_command}
    COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${latex_build_command})
  set(make_pdf_command ${make_pdf_command}
    COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${pdflatex_build_command}
    COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${pdflatex_build_command})

  # Need to run one more time to remove biblatex' warning
  # about page breaks that have changed.
  if(LATEX_USE_BIBLATEX)
    set(make_dvi_command ${make_dvi_command}
      COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
      ${latex_build_command})
    set(make_pdf_command ${make_pdf_command}
      COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
      ${pdflatex_build_command})
  endif()

  if(LATEX_USE_SYNCTEX)
    if(NOT GZIP)
      message(SEND_ERROR "UseLATEX.cmake: USE_SYNTEX option requires gzip program.  Set GZIP variable.")
    endif()
    set(make_dvi_command ${make_dvi_command}
      COMMAND ${CMAKE_COMMAND}
      -D LATEX_BUILD_COMMAND=correct_synctex
      -D LATEX_TARGET=${LATEX_TARGET}
      -D GZIP=${GZIP}
      -D "LATEX_SOURCE_DIRECTORY=${CMAKE_CURRENT_SOURCE_DIR}"
      -D "LATEX_BINARY_DIRECTORY=${output_dir}"
      -P ${LATEX_USE_LATEX_LOCATION}
      )
    set(make_pdf_command ${make_pdf_command}
      COMMAND ${CMAKE_COMMAND}
      -D LATEX_BUILD_COMMAND=correct_synctex
      -D LATEX_TARGET=${LATEX_TARGET}
      -D GZIP=${GZIP}
      -D "LATEX_SOURCE_DIRECTORY=${CMAKE_CURRENT_SOURCE_DIR}"
      -D "LATEX_BINARY_DIRECTORY=${output_dir}"
      -P ${LATEX_USE_LATEX_LOCATION}
      )
  endif()

  # Check LaTeX output for important warnings at end of build
  set(make_dvi_command ${make_dvi_command}
    COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${CMAKE_COMMAND}
      -D LATEX_BUILD_COMMAND=check_important_warnings
      -D LATEX_TARGET=${LATEX_TARGET}
      -P ${LATEX_USE_LATEX_LOCATION}
    )
  set(make_pdf_command ${make_pdf_command}
    COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
    ${CMAKE_COMMAND}
      -D LATEX_BUILD_COMMAND=check_important_warnings
      -D LATEX_TARGET=${LATEX_TARGET}
      -P ${LATEX_USE_LATEX_LOCATION}
    )

  # Capture the default build.
  string(TOLOWER "${LATEX_DEFAULT_BUILD}" default_build)

  if((NOT LATEX_FORCE_PDF) AND (NOT LATEX_FORCE_DVI) AND (NOT LATEX_FORCE_HTML))
    set(no_force TRUE)
  endif()

  # Add commands and targets for building pdf outputs (with pdflatex).
  if(LATEX_FORCE_PDF OR no_force)
    if(LATEX_FORCE_PDF)
      set(default_build pdf)
    endif()

    if(PDFLATEX_COMPILER)
      add_custom_command(OUTPUT ${output_dir}/${LATEX_TARGET}.pdf
        COMMAND ${make_pdf_command}
        DEPENDS ${make_pdf_depends}
        )
      add_custom_target(${pdf_target}
        DEPENDS ${output_dir}/${LATEX_TARGET}.pdf
        SOURCES ${all_latex_sources}
        )
      if(NOT LATEX_EXCLUDE_FROM_DEFAULTS)
        add_dependencies(pdf ${pdf_target})
      endif()
    endif()
  endif()

  # Add commands and targets for building dvi outputs.
  if(LATEX_FORCE_DVI OR LATEX_FORCE_HTML OR no_force)
    if(LATEX_FORCE_DVI)
      if((NOT default_build STREQUAL dvi) AND
          (NOT default_build STREQUAL ps) AND
          (NOT default_build STREQUAL safepdf))
        set(default_build dvi)
      endif()
    endif()

    add_custom_command(OUTPUT ${output_dir}/${LATEX_TARGET}.dvi
      COMMAND ${make_dvi_command}
      DEPENDS ${make_dvi_depends}
      )
    add_custom_target(${dvi_target}
      DEPENDS ${output_dir}/${LATEX_TARGET}.dvi
      SOURCES ${all_latex_sources}
      )
    if(NOT LATEX_EXCLUDE_FROM_DEFAULTS)
      add_dependencies(dvi ${dvi_target})
    endif()

    if(DVIPS_CONVERTER)
      add_custom_command(OUTPUT ${output_dir}/${LATEX_TARGET}.ps
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
        ${DVIPS_CONVERTER} ${DVIPS_CONVERTER_ARGS} -o ${LATEX_TARGET}.ps ${LATEX_TARGET}.dvi
        DEPENDS ${output_dir}/${LATEX_TARGET}.dvi)
      add_custom_target(${ps_target}
        DEPENDS ${output_dir}/${LATEX_TARGET}.ps
        SOURCES ${all_latex_sources}
        )
      if(NOT LATEX_EXCLUDE_FROM_DEFAULTS)
        add_dependencies(ps ${ps_target})
      endif()
      if(PS2PDF_CONVERTER)
        # Since both the pdf and safepdf targets have the same output, we
        # cannot properly do the dependencies for both.  When selecting safepdf,
        # simply force a recompile every time.
        add_custom_target(${safepdf_target}
          ${CMAKE_COMMAND} -E chdir ${output_dir}
          ${PS2PDF_CONVERTER} ${PS2PDF_CONVERTER_ARGS} ${LATEX_TARGET}.ps ${LATEX_TARGET}.pdf
          DEPENDS ${ps_target}
          )
        if(NOT LATEX_EXCLUDE_FROM_DEFAULTS)
          add_dependencies(safepdf ${safepdf_target})
        endif()
      endif()
    endif()
  endif()

  if(LATEX_FORCE_HTML OR no_force)
    if (LATEX_FORCE_HTML)
      set(default_build html)
    endif()

    if(HTLATEX_COMPILER AND LATEX_MAIN_INPUT_SUBDIR)
      message(STATUS
        "Disabling HTML build for ${LATEX_TARGET_NAME}.tex because the main file is in subdirectory ${LATEX_MAIN_INPUT_SUBDIR}"
        )
      # The code below to run HTML assumes that LATEX_TARGET.tex is in the
      # current directory. I have tried to specify that LATEX_TARGET.tex is
      # in a subdirectory. That makes the build targets correct, but the
      # HTML build still fails (at least for htlatex) because files are not
      # generated where expected. I am getting around the problem by simply
      # disabling HTML in this case. If someone really cares, they can fix
      # this, but make sure it runs on many platforms and build programs.
    elseif(HTLATEX_COMPILER)
      # htlatex places the output in a different location
      set(HTML_OUTPUT "${output_dir}/${LATEX_TARGET}.html")
      add_custom_command(OUTPUT ${HTML_OUTPUT}
        COMMAND ${CMAKE_COMMAND} -E chdir ${output_dir}
          ${HTLATEX_COMPILER} ${LATEX_MAIN_INPUT}
          "${HTLATEX_COMPILER_TEX4HT_FLAGS}"
          "${HTLATEX_COMPILER_TEX4HT_POSTPROCESSOR_FLAGS}"
          "${HTLATEX_COMPILER_T4HT_POSTPROCESSOR_FLAGS}"
          ${HTLATEX_COMPILER_ARGS}
        DEPENDS
          ${output_dir}/${LATEX_TARGET}.tex
          ${output_dir}/${LATEX_TARGET}.dvi
        VERBATIM
        )
      add_custom_target(${html_target}
        DEPENDS ${HTML_OUTPUT} ${dvi_target}
        SOURCES ${all_latex_sources}
        )
      if(NOT LATEX_EXCLUDE_FROM_DEFAULTS)
        add_dependencies(html ${html_target})
      endif()
    endif()
  endif()

  # Set default targets.
  if("${default_build}" STREQUAL "pdf")
    add_custom_target(${LATEX_TARGET_NAME} DEPENDS ${pdf_target})
  elseif("${default_build}" STREQUAL "dvi")
    add_custom_target(${LATEX_TARGET_NAME} DEPENDS ${dvi_target})
  elseif("${default_build}" STREQUAL "ps")
    add_custom_target(${LATEX_TARGET_NAME} DEPENDS ${ps_target})
  elseif("${default_build}" STREQUAL "safepdf")
    add_custom_target(${LATEX_TARGET_NAME} DEPENDS ${safepdf_target})
  elseif("${default_build}" STREQUAL "html")
    add_custom_target(${LATEX_TARGET_NAME} DEPENDS ${html_target})
  else()
    message(SEND_ERROR "LATEX_DEFAULT_BUILD set to an invalid value. See the documentation for that variable.")
  endif()

  if(NOT LATEX_EXCLUDE_FROM_ALL)
    add_custom_target(_${LATEX_TARGET_NAME} ALL DEPENDS ${LATEX_TARGET_NAME})
  endif()

  set_directory_properties(.
    ADDITIONAL_MAKE_CLEAN_FILES "${auxiliary_clean_files}"
    )

  add_custom_target(${auxclean_target}
    COMMENT "Cleaning auxiliary LaTeX files."
    COMMAND ${CMAKE_COMMAND} -E remove ${auxiliary_clean_files}
    )
  add_dependencies(auxclean ${auxclean_target})
endfunction(add_latex_targets_internal)

function(add_latex_targets latex_main_input)
  latex_get_output_path(output_dir)
  parse_add_latex_arguments(ADD_LATEX_TARGETS ${latex_main_input} ${ARGN})

  add_latex_targets_internal()
endfunction(add_latex_targets)

function(add_latex_document latex_main_input)
  process_markup_file(latex_main_input)
  latex_get_output_path(output_dir)
  if(output_dir)
    parse_add_latex_arguments(add_latex_document ${latex_main_input} ${ARGN})

    latex_copy_input_file(${LATEX_MAIN_INPUT})

    foreach (bib_file ${LATEX_BIBFILES})
      latex_copy_input_file(${bib_file})
    endforeach (bib_file)

    if (LATEX_USE_BIBLATEX AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/biblatex.cfg)
      latex_copy_input_file(biblatex.cfg)
      set(LATEX_USE_BIBLATEX_CONFIG TRUE)
    endif()

    foreach (input ${LATEX_INPUTS})
      latex_copy_input_file(${input})
    endforeach(input)

    latex_copy_globbed_files(${CMAKE_CURRENT_SOURCE_DIR}/*.cls ${output_dir})
    latex_copy_globbed_files(${CMAKE_CURRENT_SOURCE_DIR}/*.bst ${output_dir})
    latex_copy_globbed_files(${CMAKE_CURRENT_SOURCE_DIR}/*.clo ${output_dir})
    latex_copy_globbed_files(${CMAKE_CURRENT_SOURCE_DIR}/*.sty ${output_dir})
    latex_copy_globbed_files(${CMAKE_CURRENT_SOURCE_DIR}/*.ist ${output_dir})
    latex_copy_globbed_files(${CMAKE_CURRENT_SOURCE_DIR}/*.fd  ${output_dir})

    add_latex_targets_internal()
  endif()
endfunction(add_latex_document)

#############################################################################
# Actually do stuff
#############################################################################

if(LATEX_BUILD_COMMAND)
  set(command_handled)

  if("${LATEX_BUILD_COMMAND}" STREQUAL execute_latex)
    latex_execute_latex()
    set(command_handled TRUE)
  endif()

  if("${LATEX_BUILD_COMMAND}" STREQUAL makeglossaries)
    latex_makeglossaries()
    set(command_handled TRUE)
  endif()

  if("${LATEX_BUILD_COMMAND}" STREQUAL makenomenclature)
    latex_makenomenclature()
    set(command_handled TRUE)
  endif()

  if("${LATEX_BUILD_COMMAND}" STREQUAL correct_synctex)
    latex_correct_synctex()
    set(command_handled TRUE)
  endif()

  if("${LATEX_BUILD_COMMAND}" STREQUAL check_important_warnings)
    latex_check_important_warnings()
    set(command_handled TRUE)
  endif()

  if(NOT command_handled)
    message(SEND_ERROR "Unknown command: ${LATEX_BUILD_COMMAND}")
  endif()

else()
  # Must be part of the actual configure (included from CMakeLists.txt).
  latex_setup_variables()
  latex_setup_targets()
endif()
