# Vendorboot
Magisk vendor_boot patcher using Google Colab

## Usage

Step 1) Upload your vendor_boot.img file to [Google Colab](https://colab.research.google.com/#create=true).

Step 2) Change architecture according your device in last line like arm, arm64, x86, x86_64

Step 3) Paste the code below into a Colab code cell and run it after uploading vendor_boot.img. 


```bash
!apt-get update -y && apt-get upgrade -y
!apt-get install -y git wget jq cpio unzip gzip xz-utils lz4 tar

!git clone https://github.com/777nrv/vendorboot
%cd vendorboot

!chmod +x patch.sh

!mv /content/vendor_boot.img ./

!./patch.sh --target-arch arm64 vendor_boot.img
```
