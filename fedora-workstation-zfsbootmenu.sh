source /etc/os-release
export ID

rpm -e --nodeps zfs-fuse

dnf5 config-manager --set-disabled updates

dnf --releasever=${VERSION_ID} install -y \
  https://zfsonlinux.org/fedora/zfs-release-3-0$(rpm --eval "%{dist}").noarch.rpm

dnf install -y https://dl.fedoraproject.org/pub/fedora/linux/releases/${VERSION_ID}/Everything/x86_64/os/Packages/k/kernel-devel-$(uname -r).rpm

dnf install -y zfs

zgenhostid -f 0x00bab10c

export BOOT_DISK="/dev/nvme0n1"
export BOOT_PART="1"
export BOOT_DEVICE="${BOOT_DISK}p${BOOT_PART}"

export POOL_DISK="/dev/nvme0n1"
export POOL_PART="2"
export POOL_DEVICE="${POOL_DISK}p${POOL_PART}"

zpool import -f rpool

zfs create -o mountpoint=/ -o canmount=noauto rpool/ROOT/${ID}

zpool set bootfs=rpool/ROOT/${ID} rpool

zpool export rpool
zpool import -N -R /mnt rpool
zfs mount rpool/ROOT/${ID}
zfs mount rpool/home

udevadm trigger

mkdir -pv /run/install
mount /dev/loop0 /run/install -o ro

rsync -pogAXtlHrDx \
 --stats \
 --exclude=/boot/efi/* \
 --exclude=/etc/machine-id \
 --info=progress2 \
 /run/install/ /mnt

mv /mnt/etc/resolv.conf /mnt/etc/resolv.conf.orig
cp -L /etc/resolv.conf /mnt/etc
cp /etc/hostid /mnt/etc

mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount -B /dev /mnt/dev
mount -t devpts pts /mnt/dev/pts
cat <<-CHROOT | chroot /mnt /bin/bash -

mkdir -pv /boot/efi/EFI

cat << EOF > /etc/dracut.conf.d/zol.conf
nofsck="yes"
add_dracutmodules+=" zfs "
omit_dracutmodules+=" btrfs "
EOF

source /etc/os-release

dnf5 config-manager --set-disabled updates

dnf --releasever=${VERSION_ID} install -y \
  https://zfsonlinux.org/fedora/zfs-release-3-0$(rpm --eval "%{dist}").noarch.rpm

dnf install -y https://dl.fedoraproject.org/pub/fedora/linux/releases/${VERSION_ID}/Everything/x86_64/os/Packages/k/kernel-devel-$(uname -r).rpm

dnf install -y zfs

dnf install -y zfs-dracut

dnf5 config-manager --set-enable updates

dracut --force --regenerate-all

zfs set org.zfsbootmenu:commandline="quiet rhgb" rpool/ROOT

#cat << EOF >> /etc/fstab
#$( blkid | grep "$BOOT_DEVICE" | cut -d ' ' -f 2 ) /boot/efi vfat defaults 0 0
#EOF

#mount /boot/efi

#efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
#  -L "ZFSBootMenu" \
#  -l '\EFI\ZBM\VMLINUZ.EFI'

mv /etc/resolv.conf.orig /etc/resolv.conf

CHROOT
#exit

umount -n -R /mnt

zpool export rpool
#reboot
