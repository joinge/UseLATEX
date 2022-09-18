cmake_minimum_required(VERSION 2.8.12)

project(IncludeDirectory NONE)

include(../../UseLATEX.cmake)

set(UseLATEX_TEST_NAME "adding include directories")

add_latex_document(IncludeStuff.tex
  INPUTS CopiedInput.tex copied-subdir/CopiedInSubdir.tex
  INCLUDE_DIRECTORIES
    copied-subdir
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/uncopied-subdir
  CONFIGURE IncludeStuff.tex CopiedInput.tex copied-subdir/CopiedInSubdir.tex
  )
