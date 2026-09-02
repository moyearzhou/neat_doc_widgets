cmake_minimum_required(VERSION 3.5.0)
project(syncfusion_pdf_renderer)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(pdfium SHARED IMPORTED)
set_target_properties(pdfium PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/../libs/${OHOS_ARCH}/libpdfium.so
)

add_library(pdf_renderer SHARED pdf_renderer_napi.cpp)
target_include_directories(pdf_renderer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_options(pdf_renderer PRIVATE -O2)
target_link_libraries(pdf_renderer PUBLIC libace_napi.z.so libhilog_ndk.z.so pdfium)
