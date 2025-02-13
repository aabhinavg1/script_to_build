#!/bin/bash
# download the exisiting mode 
#  wget https://huggingface.co/qualcomm/MobileNet-v2/resolve/main/MobileNet-v2.tflite -O mobilenet_v2.tflite
# Exit on any error
set -e

# Ensure correct usage
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tflite_model>"
  echo "Example: $0 model.tflite"
  exit 1
fi

# Input TFLite model
TFLITE_MODEL=$1

# Check if file exists
if [[ ! -f "$TFLITE_MODEL" ]]; then
  echo "Error: File '$TFLITE_MODEL' not found!"
  exit 1
fi

# Function to install required dependencies
install_dependencies() {
  echo "Installing required dependencies..."
  if [[ $(uname -s) == "Darwin" ]]; then
    # For macOS
    brew install cmake ninja clang python3
  else
    # For Ubuntu/Debian-based Linux (ARM)
    sudo apt update
    sudo apt install cmake ninja-build clang python3-pip
  fi
}

# Install dependencies if they are not already installed
if ! command -v cmake &>/dev/null || ! command -v ninja &>/dev/null || ! command -v clang &>/dev/null; then
  install_dependencies
else
  echo "Required dependencies are already installed."
fi

# Clone IREE from GitHub
if [[ ! -d "iree" ]]; then
  echo "Cloning IREE repository..."
  git clone --recurse-submodules https://github.com/openxla/iree.git
  cd iree
else
  echo "IREE repository already cloned."
  cd iree
  git pull
  git submodule update --init --recursive
fi

# Create build directory and navigate into it
mkdir -p build
cd build

# Configure the build using CMake
echo "Configuring IREE build with CMake..."
cmake -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DIREE_BUILD_EXAMPLES=ON \
  -DIREE_ENABLE_LLVM=ON \
  -DIREE_HAL_DRIVER_VULKAN=ON \
  -DIREE_ENABLE_PYTHON=ON \
  ..

# Build IREE with Ninja
echo "Building IREE from source..."
ninja

# Add IREE tools to PATH
export PATH=$PWD/iree-build/tools:$PATH

# Get filename without extension
MODEL_NAME=$(basename "$TFLITE_MODEL" .tflite)

# Convert TFLite to MLIR
MLIR_FILE="${MODEL_NAME}.mlir"
echo "Converting TFLite model to MLIR..."
iree-import-tflite --input_file="$TFLITE_MODEL" --output_file="$MLIR_FILE"

# Check if MLIR file was created successfully
if [[ ! -f "$MLIR_FILE" ]]; then
  echo "Error: MLIR file conversion failed!"
  exit 1
fi

# Convert MLIR to SPIR-V
SPV_FILE="${MODEL_NAME}.spv"
echo "Compiling MLIR to SPIR-V..."
iree-compile "$MLIR_FILE" \
  --iree-hal-target-backends=spirv-vulkan \
  -o "$SPV_FILE"

# Check if SPIR-V file was created successfully
if [[ ! -f "$SPV_FILE" ]]; then
  echo "Error: SPIR-V file compilation failed!"
  exit 1
fi

echo "✅ Conversion complete! SPIR-V binary saved as: $SPV_FILE"
