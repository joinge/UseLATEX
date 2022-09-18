cmake_minimum_required(VERSION 2.8.12)

project(DefaultTargets NONE)

include(../../UseLATEX.cmake)

add_latex_document(DefaultDvi.tex IMAGE_DIRS images FORCE_DVI)
add_latex_document(DefaultPdf.tex IMAGE_DIRS images FORCE_PDF)
add_latex_document(DefaultHtml.tex IMAGE_DIRS images FORCE_HTML)
add_latex_document(NoDefault.tex IMAGE_DIRS images EXCLUDE_FROM_ALL)
