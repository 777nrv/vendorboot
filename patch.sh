#!/bin/bash

KEEPVERITY=true
KEEPFORCEENCRYPT=true
RECOVERYMODE=false
HOST_ARCH=$(uname -m)
CURRENT_DEVICE=true

show_help() {
    echo "Usage: ./patch.sh [options] <vendor_boot.img>"
    echo "Options:"
    echo "  --help                  Show this help message and exit"
    echo "  --no-verity             Disable verity"
    echo "  --no-forceencrypt       Disable forceencrypt"
    echo "  --target-arch <arch>    Specify target arch (x86, x86_64, arm, arm64)"
    exit 0
}

if [[ -z $(command -v jq) ]]; then
    echo "Error: jq is not installed"
    exit 1
fi
if [[ -z $(command -v cpio) ]]; then
    echo "Error: cpio is not installed"
    exit 1
fi
if [[ -z $(command -v wget) ]]; then
    echo "Error: wget is not installed"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            show_help
            ;;
        --no-verity)
            KEEPVERITY=false
            shift
            ;;
        --no-forceencrypt)
            KEEPFORCEENCRYPT=false
            shift
            ;;
        --target-arch)
            if [[ -z $2 ]]; then
                echo "Error: Missing argument for $1"
                exit 1
            fi
            ARCH=$2
            shift 2
            ;;
        *)
            if [[ -z "$FILE" ]]; then
                VENDORBOOT_IMG=$1
                shift
            else
                echo "Error: Unknown option or extra argument: $1"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$VENDORBOOT_IMG" ]]; then
    echo "Error: No input file provided."
    exit 1
fi

echo "Downloading Magisk stable..."
json_data=$(curl -L https://github.com/topjohnwu/magisk-files/raw/master/stable.json)
wget -q -O magisk.zip $(echo $json_data | jq -r '.magisk.link') || { echo "Error: Failed to download Magisk"; exit 1; }

case $HOST_ARCH in
    x86) HOST_ARCH=x86; TARGET_ARCH=x86 ;;
    x86_64) HOST_ARCH=x86_64; TARGET_ARCH=x86_64 ;;
    armv7l) HOST_ARCH=armeabi-v7a; TARGET_ARCH=armeabi-v7a ;;
    aarch64) HOST_ARCH=arm64-v8a; TARGET_ARCH=arm64-v8a ;;
esac
if [[ -n $ARCH ]]; then
    case $ARCH in
        x86) TARGET_ARCH=x86 ;;
        x86_64) TARGET_ARCH=x86_64 ;;
        arm) TARGET_ARCH=armeabi-v7a ;;
        arm64) TARGET_ARCH=arm64-v8a ;;
    esac
fi

echo "Extracting Magisk files..."
mkdir .temp
cd .temp
unzip ../magisk.zip > /dev/null 2>&1
cp lib/$HOST_ARCH/libmagiskboot.so ../magiskboot
cp lib/$TARGET_ARCH/libmagisk.so ../magisk
cp lib/$TARGET_ARCH/libmagiskinit.so ../magiskinit
cp lib/$TARGET_ARCH/libinit-ld.so ../init-ld
cp assets/stub.apk ../stub.apk
cd ..
chmod a+x magiskboot magisk magiskinit init-ld

echo "Compressing files..."
./magiskboot compress=xz magisk magisk.xz
./magiskboot compress=xz stub.apk stub.xz
./magiskboot compress=xz init-ld init-ld.xz

echo "Writing config..."
echo "KEEPVERITY=$KEEPVERITY" > config
echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
echo "RECOVERYMODE=$RECOVERYMODE" >> config
PREINITDEVICE=$(./magisk --preinit-device)
echo "Pre-init storage partition: $PREINITDEVICE"
echo "PREINITDEVICE=$PREINITDEVICE" >> config
echo "SHA1=$(./magiskboot sha1 $VENDORBOOT_IMG)" >> config

echo "Unpacking vendor boot image..."
./magiskboot unpack $VENDORBOOT_IMG > /dev/null 2>&1 || { echo "Error: Failed to unpack vendor boot image"; exit 1; }

if [[ -z "vendor_ramdisk/init_boot.cpio" ]]; then
    echo "Error: init_boot not found in vendor boot image"
    exit 1
fi

echo "Patching ramdisk..."
cp vendor_ramdisk/init_boot.cpio ramdisk.cpio
cp vendor_ramdisk/init_boot.cpio ramdisk.cpio.orig
./magiskboot cpio ramdisk.cpio \
"add 0750 init magiskinit" \
"mkdir 0750 overlay.d" \
"mkdir 0750 overlay.d/sbin" \
"add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
"add 0644 overlay.d/sbin/stub.xz stub.xz" \
"add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
"patch" \
"backup ramdisk.cpio.orig" \
"mkdir 000 .backup" \
"add 000 .backup/.magisk config" > /dev/null 2>&1 || { echo "Error: Failed to patch ramdisk"; exit 1; }
cp ramdisk.cpio vendor_ramdisk/init_boot.cpio

for dt in dtb kernel_dtb extra; do
    if [ -f $dt ]; then
        if ! ./magiskboot dtb $dt test; then
            echo "! Boot image $dt was patched by old (unsupported) Magisk"
            exit 1
        fi
        ./magiskboot dtb $dt patch && echo "Patch fstab in boot image $dt"
    fi
done

echo "Repacking vendor boot image..."
./magiskboot repack $VENDORBOOT_IMG > /dev/null 2>&1 || { echo "Error: Failed to repack vendor boot image"; exit 1; }
mv new-boot.img vendor_boot_patched.img

echo "Cleaning up..."
rm -rf magisk.zip magiskboot magisk magiskinit stub.apk init-ld magisk.xz stub.xz init-ld.xz config ramdisk.cpio ramdisk.cpio.orig vendor_ramdisk dtb .temp

