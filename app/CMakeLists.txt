# Required first entry checking the cmake version.
cmake_minimum_required(VERSION 3.18)
# Set the project name.
project("hello-world" LANGUAGES CXX)

# Make it so our own packages are found.
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_LIST_DIR}/../com/cmake")
# Make sure builds do not wind up in the source directory.
find_package(SfBuildCheck CONFIG REQUIRED)
find_package(SfMacros CONFIG REQUIRED)
find_package(SfCompiler CONFIG REQUIRED)

# Set the 3 CMAKE_xxxxx_OUTPUT_DIRECTORY variables.
Sf_SetOutputDirs()

# Set the actual executable target.
Sf_AddExecutable(${PROJECT_NAME})

# Add version resource to the target.
Sf_AddVersionResource("${PROJECT_NAME}")

# Add custom target to report resource stored versions.
Sf_AddExifTarget("${PROJECT_NAME}")

# RC-files only seem to be compiled when building using MingW.
target_sources(${PROJECT_NAME} PRIVATE main.cpp)

# Add this for the headers in the autogen directory made by the *.ui files.
set(CMAKE_INCLUDE_CURRENT_DIR ON)

# Sets the extension of the generated binary.
Sf_SetBinarySuffix("${PROJECT_NAME}")

add_subdirectory(tests)
