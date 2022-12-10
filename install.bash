#!/bin/bash

# Check for required dependencies
dependencies=(curl qemu-system-x86_64 cloud-localds)
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" > /dev/null 2>&1; then
        echo "Error: $dep is not installed" >&2
        exit 1
    fi
done

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -m|--memory)
            VM_MEMORY="$2"
            shift
            shift
            ;;
        -p|--port)
            VM_SSH_PORT="$2"
            shift
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Use default values if not set
VM_MEMORY=${VM_MEMORY:-4096M}
VM_SSH_PORT=${VM_SSH_PORT:-5511}
VM_UUID="6ba7b810-9dad-11d1-80b4-00c04fd430c8"

URL=https://cloud.debian.org/images/cloud/bullseye/latest
FILE=debian-11-generic-amd64.raw
BACKING_FILE=debian-11-generic-amd64-backing_file.raw

SHA_512=$(curl -sL "$URL/SHA512SUMS" | grep "$FILE" | awk '{print $1}')

# Cloud-init config
VM_INSTANCE=debian-001
VM_HOST=devbox
SEED_IMAGE_FILE=seed.img 
USER_DATA_FILE=user-data.yaml
META_DATA_FILE=meta-data.yaml
SSH_KEY_NAME=id_rsa

if [ -f "$FILE" ]; then
    echo "$FILE exists locally, don't download"
    echo "validating checksum"
    if ! echo "$SHA_512 $FILE" | sha512sum -c -; then
        echo "Checksum failed" >&2
        exit 1
    fi
else 
    echo "$FILE doesn't exist downloading from $URL/$FILE"
    curl -L -O $URL/$FILE
    echo "validating checksum"
    if ! echo "$SHA_512 $FILE" | sha512sum -c -; then
        echo "Checksum failed" >&2
        exit 1
    fi
fi
echo "creating backing file ($BACKING_FILE) for $FILE"
cp $FILE $BACKING_FILE


echo "creating ssh key pair for vm"
ssh-keygen -t rsa -b 4096 -f $SSH_KEY_NAME -q -N ""

SSH_PUBLIC_KEY=`cat $SSH_KEY_NAME.pub`

cat <<EOF >> $META_DATA_FILE
instance-id: $VM_INSTANCE
local-hostname: $VM_HOST
EOF

cat <<EOF >> $USER_DATA_FILE
#cloud-config
ssh_authorized_keys:
  - $SSH_PUBLIC_KEY
EOF

echo "creating seed image for cloud-init"
cloud-localds $SEED_IMAGE_FILE $USER_DATA_FILE $META_DATA_FILE


echo "wait for the VM to boot"
echo "use the following command to ssh"
echo "ssh -i $SSH_KEY_NAME -p $VM_SSH_PORT debian@localhost"

qemu-system-x86_64 \
    -device "virtio-net,netdev=user.0" \
    -machine "type=q35,accel=kvm" \
    -boot "c" \
    -m "$VM_MEMORY" \
    -mem-prealloc \
    -uuid "$VM_UUID" \
    -netdev "user,id=user.0,hostfwd=tcp::$VM_SSH_PORT-:22" \
    -drive file=$PWD/$BACKING_FILE,if=virtio,cache=writeback,discard=ignore,format=raw \
    -drive if=virtio,format=raw,file=$SEED_IMAGE_FILE
