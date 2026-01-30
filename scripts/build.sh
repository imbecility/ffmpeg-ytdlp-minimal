#!/bin/bash
set -e

TARGET=$1
BASE_DIR="$(pwd)"
INSTALL_DIR="$BASE_DIR/build_deps"
OUTPUT_DIR="$BASE_DIR/output"
mkdir -p "$INSTALL_DIR" "$OUTPUT_DIR"

if [ "$TARGET" == "windows" ]; then
    CROSS_PREFIX="x86_64-w64-mingw32-"
    HOST="x86_64-w64-mingw32"
    TARGET_OS="mingw32"
    STRIP="x86_64-w64-mingw32-strip"
    FFMPEG_EXE="ffmpeg.exe"
    CMAKE_SYS_NAME="Windows"
    EXTRA_LIBS=""
else
    CROSS_PREFIX=""
    HOST=""
    TARGET_OS="linux"
    STRIP="strip"
    FFMPEG_EXE="ffmpeg"
    CMAKE_SYS_NAME="Linux"
    EXTRA_LIBS="-lm -lstdc++"
fi

export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig"
export CFLAGS="-I$INSTALL_DIR/include -Os"
export LDFLAGS="-L$INSTALL_DIR/lib"

echo "=== Building Zlib ==="
git clone --depth 1 https://github.com/madler/zlib.git
cd zlib
if [ "$TARGET" == "windows" ]; then
    make -f win32/Makefile.gcc PREFIX=$CROSS_PREFIX
    make -f win32/Makefile.gcc install \
        PREFIX=$CROSS_PREFIX \
        BINARY_PATH="$INSTALL_DIR/bin" \
        INCLUDE_PATH="$INSTALL_DIR/include" \
        LIBRARY_PATH="$INSTALL_DIR/lib"
else
    ./configure --prefix="$INSTALL_DIR" --static
    make -j$(nproc) install
fi
cd ..

echo "=== Building Libopus ==="
git clone --depth 1 https://github.com/xiph/opus.git
cd opus
./autogen.sh
CC=${CROSS_PREFIX}gcc ./configure \
    --host=$HOST \
    --prefix="$INSTALL_DIR" \
    --enable-static \
    --disable-shared
make -j$(nproc) install
cd ..

echo "=== Building Libsoxr ==="
git clone --depth 1 https://github.com/chirlu/soxr.git
cd soxr
mkdir build && cd build
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_C_COMPILER="${CROSS_PREFIX}gcc" \
    -DCMAKE_SYSTEM_NAME=$CMAKE_SYS_NAME \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DWITH_OPENMP=OFF \
    -DWITH_LSR=OFF
make -j$(nproc) install

mkdir -p "$INSTALL_DIR/lib/pkgconfig"
cat > "$INSTALL_DIR/lib/pkgconfig/soxr.pc" <<EOF
prefix=$INSTALL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: soxr
Description: High quality, one-dimensional sample-rate conversion library
Version: 0.1.3
Libs: -L\${libdir} -lsoxr
Libs.private: -lm
Cflags: -I\${includedir}
EOF
echo "Generated soxr.pc."
cd ../..

echo "=== Debug: Checking pkg-config for soxr ==="
pkg-config --static --libs --cflags soxr || echo "pkg-config failed for soxr!"

echo "=== Building FFmpeg ==="
git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git
cd ffmpeg

if ! ./configure \
  --prefix="$OUTPUT_DIR" \
  --target-os=$TARGET_OS \
  ${HOST:+--arch=x86_64 --cross-prefix=$CROSS_PREFIX} \
  --pkg-config="pkg-config" \
  --pkg-config-flags="--static" \
  --extra-cflags="$CFLAGS" \
  --extra-ldflags="$LDFLAGS" \
  --extra-libs="$EXTRA_LIBS" \
  --enable-static --disable-shared \
  --disable-all \
  --enable-ffmpeg \
  --enable-ffmprobe \
  --enable-avcodec --enable-avformat --enable-avfilter --enable-swresample \
  --enable-small --disable-doc --disable-debug --disable-network --disable-autodetect --disable-hwaccels --disable-devices \
  --enable-protocol=file,pipe \
  --enable-zlib \
  --enable-demuxer=* --enable-decoder=* --enable-parser=* \
  --enable-encoder=libopus,flac,pcm_s16le,pcm_s24le,pcm_f32le \
  --enable-muxer=wav,ogg,flac,opus,mp4,matroska,webm,mov,ipod,adts,null \
  --enable-filter=aresample,pan,volume,loudnorm,atrim,asetpts,aformat,anull,concat,abuffer,asink \
  --enable-libopus --enable-libsoxr \
  --enable-nonfree; then
      echo "ERROR: FFmpeg configure failed!"
      echo "=== TAIL OF CONFIG.LOG ==="
      tail -n 200 ffbuild/config.log
      exit 1
fi

make -j$(nproc)
$STRIP $FFMPEG_EXE
cp $FFMPEG_EXE "$OUTPUT_DIR/"
