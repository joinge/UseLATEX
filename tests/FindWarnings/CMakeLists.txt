cmake_minimum_required(VERSION 2.8.12)

project(FindWarnings NONE)

include(../../UseLATEX.cmake)

add_latex_document(UndefinedReference.tex)

add_latex_document(UndefinedReferenceLong.tex)

add_latex_document(Natbib.tex)

add_latex_document(Overfull.tex)

add_latex_document(DuplicateLabel.tex)
