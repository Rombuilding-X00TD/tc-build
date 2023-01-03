#!/usr/bin/env bash
# Simple script by XSans0

# Function to show an informational message
msg() {
    echo -e "\e[1;32m$*\e[0m"
}

err() {
    echo -e "\e[1;41m$*\e[0m"
}

# Environment checker
if [ -z "$1" ] || [ -z "$GIT_TOKEN" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT" ]; then
    err "* Environment has missing"
    exit
fi

# Home directory
HOME="$(pwd)"

update_pkg(){
    # Update packages
    msg "* Update packages"
    sudo apt-get update && upgrade -y
}

deps() {
    # Install/update dependency
    msg "* Install/update dependency"
    sudo apt install -y \
            bc \
            binutils-dev \
            bison \
            build-essential \
            ca-certificates \
            ccache \
            clang \
            cmake \
            curl \
            file \
            flex \
            git \
            libelf-dev \
            libssl-dev \
            lld \
            make \
            ninja-build \
            python3-dev \
            texinfo \
            u-boot-tools \
            xz-utils \
            zlib1g-dev
}

build() {
    # Start build LLVM's
    msg "* Building LLVM"
    ./build-llvm.py \
        --assertions \
        --clang-vendor "KryptoNite" \
	--defines LLVM_PARALLEL_COMPILE_JOBS=$(nproc) LLVM_PARALLEL_LINK_JOBS=$(nproc) CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3 \
	--incremental \
	--lto thin \
	--projects "clang;lld;polly;compiler-rt" \
	--pgo kernel-defconfig \
	--shallow-clone \
	--targets "ARM;AArch64"

    # Check if the final clang binary exists or not.
    for file in install/bin/clang-1*
    do
        if [ -e "$file" ]; then
            msg "LLVM building successful"
        else 
            err "LLVM build failed!"
            exit
        fi
    done

    # Start build binutils
    msg "Building binutils"
./build-binutils.py --targets arm aarch64

    # Remove unused products
    rm -fr install/include
    rm -f install/lib/*.a install/lib/*.la

# Strip remaining products
for f in $(find install -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
	strip -s "${f: : -1}"
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
for bin in $(find install -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
	# Remove last character from file output (':')
	bin="${bin: : -1}"

	echo "$bin"
	patchelf --set-rpath "$DIR/install/lib" "$bin"
done

push() {
# Release Info
pushd llvm-project || exit
llvm_commit="$(git rev-parse HEAD)"
short_llvm_commit="$(cut -c-8 <<< "$llvm_commit")"
popd || exit

llvm_commit_url="https://github.com/llvm/llvm-project/commit/$short_llvm_commit"
binutils_ver="$(ls | grep "^binutils-" | sed "s/binutils-//g")"
clang_version="$(install/bin/clang --version | head -n1 | cut -d' ' -f4)"

# Push to GitHub
# Update Git repository
git config --global user.name "STRK-ND"
git config --global user.email "raj15400881@gmail.com"
git clone "https://STRK-ND:$GITLAB_TOKEN@gitlab.com/STRK-ND/KryptoNite-Clang.git" rel_repo
pushd rel_repo || exit
rm -fr ./*
cp -r ../install/* .
git checkout README.md # keep this as it's not part of the toolchain itself
git add .
git commit -asm "Update to $rel_date build

LLVM commit: $llvm_commit_url
Clang Version: $clang_version
Binutils version: $binutils_ver
Builder commit: https://github.com/Rombuilding-X00TD/tc-build/commit/$builder_commit"

git push -f
popd || exit
