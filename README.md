# libToolDAQ
ToolDAQ libraries build facility

# Usage

ToolDAQ repositories are cloned at build time for different toolchain available.


## x64 

```
cmake -B build-x64
make -j -C build-x64
make -C build-x64 install
``` 

## armhf
```
cmake -B build-arm -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-arm-linux-gnueabihf.cmake
make -j -C build-arm 
make -C build-arm install
``` 


## arm64
```
cmake -B build-arm64 -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-aarch64-linux-gnu.cmake
make -j -C build-arm64 
make -C build-arm64 install
``` 
