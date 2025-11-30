#!/bin/bash
# Build script for Well.. Simple interpreter
# Compiles for the current platform

echo "Building WPM v1.1"
echo "=============================="
echo ""

# Create build directory
mkdir -p build

# Detect platform
PLATFORM=$(uname -s)
case "$PLATFORM" in
    Linux*)
        echo "Detected platform: Linux"
        OUTPUT="build/wpm"
        ;;
    Darwin*)
        echo "Detected platform: macOS"
        OUTPUT="build/wpm"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "Detected platform: Windows"
        OUTPUT="build/wpm.exe"
        ;;
    *)
        echo "Unknown platform: $PLATFORM"
        OUTPUT="build/wpm-unknown"
        ;;
esac
echo ""

# Build for current platform
echo "Building executable..."
dart compile exe wpm.dart -o "$OUTPUT"

if [ $? -eq 0 ]; then
    echo ""
    echo "=============================="
    echo "✓ Build successful!"
    echo ""
    echo "Executable: $OUTPUT"
    echo ""
    echo "To run:"
    echo "  wpm command: $OUTPUT install <package>"
    echo "  wpm help:    $OUTPUT help"
    echo ""
    echo "Note: Cross-compilation requires building on each platform."
    echo "Run this script on Linux, macOS, and Windows to build for all platforms."
else
    echo ""
    echo "✗ Build failed"
    exit 1
fi
