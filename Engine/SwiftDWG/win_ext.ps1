# Set environment variables for LibreDWG paths on Windows
$env:DWG_INCLUDE = "C:/dev/libredwg/include"
$env:DWG_LIB = "C:/dev/libredwg/build"

swift build -c debug -vv -Xcc "-I$($env:DWG_INCLUDE)" -Xcc "-IC:/dev/libredwg/src" -Xcc "-IC:/dev/libredwg/build/src"
