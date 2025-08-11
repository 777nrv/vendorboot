./magiskboot unpack "$VENDOR_IMAGE" >/dev/null || { echo "Unpack failed."; exit 1; }
[[ ! -f vendor_ramdisk/init_boot.cpio ]] && { echo "init_boot.cpio not found."; exit 1; }

cp vendor_ramdisk/init_boot.cpio ramdisk.cpio
cp vendor_ramdisk/init_boot.cpio ramdisk_backup.cpio
./magiskboot cpio ramdisk.cpio \
    "add 0750 init magiskinit" \
    "mkdir 0750 overlay.d" \
    "mkdir 0750 overlay.d/sbin" \
    "add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
    "add 0644 overlay.d/sbin/stub.xz stub.xz" \
    "add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
    "patch" \
    "backup ramdisk_backup.cpio" \
    "mkdir 000 .backup" \
    "add 000 .backup/.magisk config" >/dev/null || { echo "Ramdisk patch failed."; exit 1; }
cp ramdisk.cpio vendor_ramdisk/init_boot.cpio

for dtfile in dtb kernel_dtb extra; do
    if [[ -f $dtfile ]]; then
        ./magiskboot dtb $dtfile patch && echo "Patched fstab in $dtfile"
    fi
done

./magiskboot repack "$VENDOR_IMAGE" >/dev/null || { echo "Repack failed."; exit 1; }
NEW_IMG=$(echo "$VENDOR_IMAGE" | sed "s/.img/-patched-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8).img/")
mv new-boot.img "$NEW_IMG"

rm -rf workdir magiskboot magisk magiskinit init-ld stub.apk magisk.xz stub.xz init-ld.xz config ramdisk.cpio ramdisk_backup.cpio vendor_ramdisk dtb magisk.zip

python3 - <<EOF
from google.colab import files
print("Preparing download for:", "$NEW_IMG")
files.download("$NEW_IMG")
EOF