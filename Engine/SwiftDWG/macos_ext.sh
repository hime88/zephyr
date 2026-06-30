# Set environment variables (replace paths with your actual macOS paths)
export DWG_INCLUDE="/opt/homebrew/include"
export DWG_LIB="/opt/homebrew/lib"

# Run the swift build command
swift build -c release -vv -Xcc "-I${DWG_INCLUDE}"
