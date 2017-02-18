# virtual console keymap
set_keymap() {
    KEYMAPS=""
    for i in $(ls -R /usr/share/kbd/keymaps | grep "map.gz" | sed 's/\.map\.gz//g' | sort); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done

    DIALOG " $_VCKeymapTitle " --menu "$_VCKeymapBody" 20 40 16 ${KEYMAPS} 2>${ANSWER} || prep_menu
    KEYMAP=$(cat ${ANSWER})

    loadkeys $KEYMAP 2>/tmp/.errlog
    check_for_error

    echo -e "KEYMAP=${KEYMAP}\nFONT=${FONT}" > /tmp/vconsole.conf
}

# Set keymap for X11
set_xkbmap() {
    XKBMAP_LIST=""
    keymaps_xkb=("af al am at az ba bd be bg br bt bw by ca cd ch cm cn cz de dk ee es et eu fi fo fr\
      gb ge gh gn gr hr hu ie il in iq ir is it jp ke kg kh kr kz la lk lt lv ma md me mk ml mm mn mt mv\
      ng nl no np pc ph pk pl pt ro rs ru se si sk sn sy tg th tj tm tr tw tz ua us uz vn za")

    for i in ${keymaps_xkb}; do
        XKBMAP_LIST="${XKBMAP_LIST} ${i} -"
    done

    DIALOG " $_PrepKBLayout " --menu "$_XkbmapBody" 0 0 16 ${XKBMAP_LIST} 2>${ANSWER} || install_graphics_menu
    XKBMAP=$(cat ${ANSWER} |sed 's/_.*//')
    echo -e "Section "\"InputClass"\"\nIdentifier "\"system-keyboard"\"\nMatchIsKeyboard "\"on"\"\nOption "\"XkbLayout"\" "\"${XKBMAP}"\"\nEndSection" \
      > ${MOUNTPOINT}/etc/X11/xorg.conf.d/00-keyboard.conf
}

# locale array generation code adapted from the Manjaro 0.8 installer
set_locale() {
    LOCALES=""
    for i in $(cat /etc/locale.gen | grep -v "#  " | sed 's/#//g' | sed 's/ UTF-8//g' | grep .UTF-8); do
        LOCALES="${LOCALES} ${i} -"
    done

    DIALOG " $_ConfBseSysLoc " --menu "$_localeBody" 0 0 12 ${LOCALES} 2>${ANSWER} || config_base_menu

    LOCALE=$(cat ${ANSWER})

    echo "LANG=\"${LOCALE}\"" > ${MOUNTPOINT}/etc/locale.conf
    sed -i "s/#${LOCALE}/${LOCALE}/" ${MOUNTPOINT}/etc/locale.gen 2>/tmp/.errlog
    arch_chroot "locale-gen" >/dev/null 2>>/tmp/.errlog
    check_for_error
}

# Set Zone and Sub-Zone
set_timezone() {
    ZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud); do
        ZONE="$ZONE ${i} -"
    done

    DIALOG " $_ConfBseTimeHC " --menu "$_TimeZBody" 0 0 10 ${ZONE} 2>${ANSWER} || config_base_menu
    ZONE=$(cat ${ANSWER})

    SUBZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "${ZONE}/" | sed "s/${ZONE}\///g" | sort -ud); do
        SUBZONE="$SUBZONE ${i} -"
    done

    DIALOG " $_ConfBseTimeHC " --menu "$_TimeSubZBody" 0 0 11 ${SUBZONE} 2>${ANSWER} || config_base_menu
    SUBZONE=$(cat ${ANSWER})

    DIALOG " $_ConfBseTimeHC " --yesno "$_TimeZQ ${ZONE}/${SUBZONE}?" 0 0

    if [[ $? -eq 0 ]]; then
        arch_chroot "ln -s /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime" 2>/tmp/.errlog
        check_for_error
    else
        config_base_menu
    fi
}

set_hw_clock() {
    DIALOG " $_ConfBseTimeHC " --menu "$_HwCBody" 0 0 2 \
    "utc" "-" \
    "localtime" "-" 2>${ANSWER}

    [[ $(cat ${ANSWER}) != "" ]] && arch_chroot "hwclock --systohc --$(cat ${ANSWER})"  2>/tmp/.errlog && check_for_error
}

# Function will not allow incorrect UUID type for installed system.
generate_fstab() {
    DIALOG " $_ConfBseFstab " --menu "$_FstabBody" 0 0 4 \
      "fstabgen -p" "$_FstabDevName" \
      "fstabgen -L -p" "$_FstabDevLabel" \
      "fstabgen -U -p" "$_FstabDevUUID" \
      "fstabgen -t PARTUUID -p" "$_FstabDevPtUUID" 2>${ANSWER}

    if [[ $(cat ${ANSWER}) != "" ]]; then
        if [[ $SYSTEM == "BIOS" ]] && [[ $(cat ${ANSWER}) == "fstabgen -t PARTUUID -p" ]]; then
            DIALOG " $_ErrTitle " --msgbox "$_FstabErr" 0 0
            generate_fstab
        else
            $(cat ${ANSWER}) ${MOUNTPOINT} > ${MOUNTPOINT}/etc/fstab 2>/tmp/.errlog
            check_for_error
            [[ -f ${MOUNTPOINT}/swapfile ]] && sed -i "s/\\${MOUNTPOINT}//" ${MOUNTPOINT}/etc/fstab
        fi
    fi
    config_base_menu
}


set_hostname() {
    DIALOG " $_ConfBseHost " --inputbox "$_HostNameBody" 0 0 "manjaro" 2>${ANSWER} || config_base_menu

    echo "$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hostname 2>/tmp/.errlog
    echo -e "#<ip-address>\t<hostname.domain.org>\t<hostname>\n127.0.0.1\tlocalhost.localdomain\tlocalhost\t$(cat \
      ${ANSWER})\n::1\tlocalhost.localdomain\tlocalhost\t$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hosts 2>>/tmp/.errlog
    check_for_error
}

# Adapted and simplified from the Manjaro 0.8 and Antergos 2.0 installers
set_root_password() {
    DIALOG " $_ConfUsrRoot " --clear --insecure --passwordbox "$_PassRtBody" 0 0 \
      2> ${ANSWER} || config_base_menu
    PASSWD=$(cat ${ANSWER})

    DIALOG " $_ConfUsrRoot " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 \
      2> ${ANSWER} || config_base_menu
    PASSWD2=$(cat ${ANSWER})

    if [[ $PASSWD == $PASSWD2 ]]; then
        echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
        arch_chroot "passwd root" < /tmp/.passwd >/dev/null 2>/tmp/.errlog
        rm /tmp/.passwd
        check_for_error
    else
        DIALOG " $_ErrTitle " --msgbox "$_PassErrBody" 0 0
        set_root_password
    fi
}

# Originally adapted from the Antergos 2.0 installer
create_new_user() {
    DIALOG " $_NUsrTitle " --inputbox "$_NUsrBody" 0 0 "" 2>${ANSWER} || config_base_menu
    USER=$(cat ${ANSWER})

    # Loop while user name is blank, has spaces, or has capital letters in it.
    while [[ ${#USER} -eq 0 ]] || [[ $USER =~ \ |\' ]] || [[ $USER =~ [^a-z0-9\ ] ]]; do
        DIALOG " $_NUsrTitle " --inputbox "$_NUsrErrBody" 0 0 "" 2>${ANSWER} || config_base_menu
        USER=$(cat ${ANSWER})
    done

        DIALOG "_MirrorBranch" --radiolist " $_UseSpaceBar" 0 0 3 \
          "zsh" "-" on \
          "bash" "-" off \
          "fish" "-" off 2>/tmp/.shell
          shell=$(cat /tmp/.shell)
        # Enter password. This step will only be reached where the loop has been skipped or broken.
        DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassNUsrBody $USER\n\n" 0 0 \
          2> ${ANSWER} || config_base_menu
        PASSWD=$(cat ${ANSWER})

        DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 \
          2> ${ANSWER} || config_base_menu
        PASSWD2=$(cat ${ANSWER})

        # loop while passwords entered do not match.
        while [[ $PASSWD != $PASSWD2 ]]; do
            DIALOG " $_ErrTitle " --msgbox "$_PassErrBody" 0 0

            DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassNUsrBody $USER\n\n" 0 0 \
              2> ${ANSWER} || config_base_menu
            PASSWD=$(cat ${ANSWER})

            DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 \
              2> ${ANSWER} || config_base_menu
            PASSWD2=$(cat ${ANSWER})
        done

        # create new user. This step will only be reached where the password loop has been skipped or broken.
        DIALOG " $_ConfUsrNew " --infobox "$_NUsrSetBody" 0 0
        sleep 2

        # Create the user, set password, then remove temporary password file
        arch_chroot "groupadd ${USER}"
        arch_chroot "useradd ${USER} -m -g ${USER} -G wheel,storage,power,network,video,audio,lp -s /bin/$shell" 2>/tmp/.errlog
        check_for_error
        echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
        arch_chroot "passwd ${USER}" < /tmp/.passwd >/dev/null 2>/tmp/.errlog
        rm /tmp/.passwd
        check_for_error

        # Set up basic configuration files and permissions for user
        #arch_chroot "cp /etc/skel/.bashrc /home/${USER}"
        arch_chroot "chown -R ${USER}:${USER} /home/${USER}"
        [[ -e ${MOUNTPOINT}/etc/sudoers ]] && sed -i '/%wheel ALL=(ALL) ALL/s/^#//' ${MOUNTPOINT}/etc/sudoers
}

run_mkinitcpio() {
    clear

    KERNEL=""

    # If LVM and/or LUKS used, add the relevant hook(s)
    ([[ $LVM -eq 1 ]] && [[ $LUKS -eq 0 ]]) && sed -i 's/block filesystems/block lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>/tmp/.errlog
    ([[ $LVM -eq 1 ]] && [[ $LUKS -eq 1 ]]) && sed -i 's/block filesystems/block encrypt lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>/tmp/.errlog
    ([[ $LVM -eq 0 ]] && [[ $LUKS -eq 1 ]]) && sed -i 's/block filesystems/block encrypt filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>/tmp/.errlog
    check_for_error

    arch_chroot "mkinitcpio -P" 2>>/tmp/.errlog
    check_for_error
}

install_base() {
    # Prep variables
    echo "" > ${PACKAGES}
    echo "" > ${ANSWER}
    BTRF_CHECK=$(echo "btrfs-progs" "-" off)
    F2FS_CHECK=$(echo "f2fs-tools" "-" off)
    KERNEL="n"
    mhwd-kernel -l | awk '/linux/ {print $2}' > /tmp/.available_kernels
    kernels=$(cat /tmp/.available_kernels)

    # User to select initsystem
    DIALOG " Choose your initsystem " --menu "Some manjaro editions like gnome are incompatible with openrc" 0 0 2 \
      "1" "systemd" \
      "2" "openrc" 2>${INIT}

    if [[ $(cat ${INIT}) -eq 2 ]]; then
        touch /tmp/.openrc
        cat /usr/share/aif/package-lists/base-openrc-manjaro > /tmp/.base
    else
        [[ -e /tmp/.openrc ]] && rm /tmp/.openrc
        cat /usr/share/aif/package-lists/base-systemd-manjaro > /tmp/.base
    fi
  
    # Choose kernel and possibly base-devel
    DIALOG " $_InstBseTitle " --checklist "$_InstStandBseBody$_UseSpaceBar" 0 0 12 \
      $(cat /tmp/.available_kernels |awk '$0=$0" - off"') \
      "base-devel" "-" off 2>${PACKAGES}
      cat ${PACKAGES} >> /tmp/.base
    
    # Choose wanted kernel modules
    DIALOG " Choose additional modules for your kernels" --checklist "$_UseSpaceBar" 0 0 12 \
      "KERNEL-headers" "-" on \
      "KERNEL-acpi_call" "-" on \
      "KERNEL-ndiswrapper" "-" on \
      "KERNEL-broadcom-wl" "-" off \
      "KERNEL-r8168" "-" off \
      "KERNEL-rt3562sta" "-" off \
      "KERNEL-tp_smapi" "-" off \
      "KERNEL-vhba-module" "-" off \
      "KERNEL-virtualbox-guest-modules" "-" off \
      "KERNEL-virtualbox-host-modules" "-" off \
      "KERNEL-spl" "-" off \
      "KERNEL-zfs" "-" off 2>/tmp/.modules

    for kernel in $(cat ${PACKAGES} | grep -v "base-devel") ; do
        cat /tmp/.modules | sed "s/KERNEL/\ $kernel/g" >> /tmp/.base
    done    
    # If a selection made, act
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        clear
        # Check to see if a kernel is already installed
        ls ${MOUNTPOINT}/boot/*.img >/dev/null 2>&1
        if [[ $? == 0 ]]; then
            KERNEL="y"
        else
            for i in $(cat /tmp/.available_kernels); do
                [[ $(cat ${PACKAGES} | grep ${i}) != "" ]] && KERNEL="y" && break;
            done
        fi

        # If no kernel selected, warn and restart
        if [[ $KERNEL == "n" ]]; then
            DIALOG " $_ErrTitle " --msgbox "$_ErrNoKernel" 0 0
            install_base
        else

            # If at least one kernel selected, proceed with installation.
            basestrap ${MOUNTPOINT} $(cat /tmp/.base)

            # If root is on btrfs volume, amend mkinitcpio.conf
            [[ $(lsblk -lno FSTYPE,MOUNTPOINT | awk '/ \/mnt$/ {print $1}') == btrfs ]] && sed -e '/^HOOKS=/s/\ fsck//g' -i ${MOUNTPOINT}/etc/mkinitcpio.conf

            # If root is on nilfs2 volume, amend mkinitcpio.conf
            [[ $(lsblk -lno FSTYPE,MOUNTPOINT | awk '/ \/mnt$/ {print $1}') == nilfs2 ]] && sed -e '/^HOOKS=/s/\ fsck//g' -i ${MOUNTPOINT}/etc/mkinitcpio.conf

            # Use mhwd to install selected kernels with right kernel modules
            # This is as of yet untested
            # arch_chroot "mhwd-kernel -i $(cat ${PACKAGES} | xargs -n1 | grep -f /tmp/.available_kernels | xargs)" 
            # If the virtual console has been set, then copy config file to installation
            [[ -e /tmp/vconsole.conf ]] && cp -f /tmp/vconsole.conf ${MOUNTPOINT}/etc/vconsole.conf 2>/tmp/.errlog

            # If specified, copy over the pacman.conf file to the installation
            [[ $COPY_PACCONF -eq 1 ]] && cp -f /etc/pacman.conf ${MOUNTPOINT}/etc/pacman.conf 2>>/tmp/.errlog
            check_for_error

            # if branch was chosen, use that also in installed system. If not, use the system setting
            if [[ -e ${BRANCH} ]]; then
                sed -i "/Branch =/c\Branch = $(cat ${BRANCH})/" ${MOUNTPOINT}/etc/pacman-mirrors.conf
            else
                sed -i "/Branch =/c$(grep "Branch =" /etc/pacman-mirrors.conf)" ${MOUNTPOINT}/etc/pacman-mirrors.conf
            fi
        fi
    fi
}

install_bootloader() {
    # Grub auto-detects installed kernels, etc. Syslinux does not, hence the extra code for it.
    bios_bootloader() {
        DIALOG " $_InstBiosBtTitle " --menu "$_InstBiosBtBody" 0 0 2 \
          "grub" "-" \
          "grub + os-prober" "-" 2>${PACKAGES}
        clear

        # If something has been selected, act
        if [[ $(cat ${PACKAGES}) != "" ]]; then
            sed -i 's/+\|\"//g' ${PACKAGES}
            basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
            check_for_error

            # If Grub, select device
            if [[ $(cat ${PACKAGES} | grep "grub") != "" ]]; then
                select_device

                # If a device has been selected, configure
                if [[ $DEVICE != "" ]]; then
                    DIALOG " Grub-install " --infobox "$_PlsWaitBody" 0 0
                    arch_chroot "grub-install --target=i386-pc --recheck $DEVICE" 2>/tmp/.errlog

                    # if /boot is LVM (whether using a seperate /boot mount or not), amend grub
                    if ( [[ $LVM -eq 1 ]] && [[ $LVM_SEP_BOOT -eq 0 ]] ) || [[ $LVM_SEP_BOOT -eq 2 ]]; then
                        sed -i "s/GRUB_PRELOAD_MODULES=\"\"/GRUB_PRELOAD_MODULES=\"lvm\"/g" ${MOUNTPOINT}/etc/default/grub
                    fi

                    # If encryption used amend grub
                    [[ $LUKS_DEV != "" ]] && sed -i "s~GRUB_CMDLINE_LINUX=.*~GRUB_CMDLINE_LINUX=\"$LUKS_DEV\"~g" ${MOUNTPOINT}/etc/default/grub

                    # If root is on btrfs volume, amend grub
                    [[ $(lsblk -lno FSTYPE,MOUNTPOINT | awk '/ \/mnt$/ {print $1}') == btrfs ]] && \
                      sed -e '/GRUB_SAVEDEFAULT/ s/^#*/#/' -i ${MOUNTPOINT}/etc/default/grub

                    arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>>/tmp/.errlog
                    check_for_error
                    fi
                else
                    # Syslinux
                    DIALOG " $_InstSysTitle " --menu "$_InstSysBody" 0 0 2 \
                      "syslinux-install_update -iam" "[MBR]" "syslinux-install_update -i" "[/]" 2>${PACKAGES}

                    # If an installation method has been chosen, run it
                    if [[ $(cat ${PACKAGES}) != "" ]]; then
                        arch_chroot "$(cat ${PACKAGES})" 2>/tmp/.errlog
                        check_for_error

                    # Amend configuration file. First remove all existing entries, then input new ones.
                    sed -i '/^LABEL.*$/,$d' ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    #echo -e "\n" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                    # First the "main" entries
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux\n\tLINUX \
                      ../vmlinuz-linux\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux realtime LTS\n\tLINUX \
                      ../vmlinuz-linux-lts\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-lts.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux realtime\n\tLINUX \
                      ../vmlinuz-linux-grsec\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-grsec.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux release candidate\n\tLINUX \
                      ../vmlinuz-linux-zen\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-zen.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                    # Second the "fallback" entries
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallback\n\tLINUX \
                      ../vmlinuz-linux\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallback realtime LTS\n\tLINUX \
                      ../vmlinuz-linux-lts\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-lts-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallback realtime\n\tLINUX \
                      ../vmlinuz-linux-grsec\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-grsec-fallback.img" \
                      >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallbacl Zen\n\tLINUX \
                      ../vmlinuz-linux-zen\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-zen-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                    # Third, amend for LUKS
                    [[ $LUKS_DEV != "" ]] && sed -i "s~rw~$LUKS_DEV rw~g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                    # Finally, re-add the "default" entries
                    echo -e "\n\nLABEL hdt\n\tMENU LABEL HDT (Hardware Detection Tool)\n\tCOM32 hdt.c32" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    echo -e "\n\nLABEL reboot\n\tMENU LABEL Reboot\n\tCOM32 reboot.c32" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    echo -e "\n\n#LABEL windows\n\t#MENU LABEL Windows\n\t#COM32 chain.c32\n\t#APPEND root=/dev/sda2 rw" \
                      >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                    echo -e "\n\nLABEL poweroff\n\tMENU LABEL Poweroff\n\tCOM32 poweroff.c32" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                fi
            fi
        fi
    }

    uefi_bootloader() {
        #Ensure again that efivarfs is mounted
        [[ -z $(mount | grep /sys/firmware/efi/efivars) ]] && mount -t efivarfs efivarfs /sys/firmware/efi/efivars
    
        DIALOG " $_InstUefiBtTitle " --menu "$_InstUefiBtBody" 0 0 2 \
          "grub" "-" 2>${PACKAGES}
    
        if [[ $(cat ${PACKAGES}) != "" ]]; then
            clear
            basestrap ${MOUNTPOINT} $(cat ${PACKAGES} | grep -v "systemd-boot") efibootmgr dosfstools 2>/tmp/.errlog
            check_for_error
    
            case $(cat ${PACKAGES}) in
                "grub")
                    DIALOG " Grub-install " --infobox "$_PlsWaitBody" 0 0
                    arch_chroot "grub-install --target=x86_64-efi --efi-directory=${UEFI_MOUNT} --bootloader-id=manjaro_grub --recheck" 2>/tmp/.errlog
    
                    # If encryption used amend grub
                    [[ $LUKS_DEV != "" ]] && sed -i "s~GRUB_CMDLINE_LINUX=.*~GRUB_CMDLINE_LINUX=\"$LUKS_DEV\"~g" ${MOUNTPOINT}/etc/default/grub
    
                    # If root is on btrfs volume, amend grub
                    [[ $(lsblk -lno FSTYPE,MOUNTPOINT | awk '/ \/mnt$/ {print $1}') == btrfs ]] && \
                      sed -e '/GRUB_SAVEDEFAULT/ s/^#*/#/' -i ${MOUNTPOINT}/etc/default/grub
    
                    # Generate config file
                    arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>>/tmp/.errlog
                    check_for_error
    
                    # Ask if user wishes to set Grub as the default bootloader and act accordingly
                    DIALOG " $_InstUefiBtTitle " --yesno \
                      "$_SetBootDefBody ${UEFI_MOUNT}/EFI/boot $_SetBootDefBody2" 0 0
    
                    if [[ $? -eq 0 ]]; then
                        arch_chroot "mkdir ${UEFI_MOUNT}/EFI/boot" 2>/tmp/.errlog
                        arch_chroot "cp -r ${UEFI_MOUNT}/EFI/arch_grub/grubx64.efi ${UEFI_MOUNT}/EFI/boot/bootx64.efi" 2>>/tmp/.errlog
                        check_for_error
                        DIALOG " $_InstUefiBtTitle " --infobox "\nGrub $_SetDefDoneBody" 0 0
                        sleep 2
                    fi
                    ;;
                "systemd-boot")
                    arch_chroot "bootctl --path=${UEFI_MOUNT} install" 2>/tmp/.errlog
                    check_for_error
    
                    # Deal with LVM Root
                    [[ $(echo $ROOT_PART | grep "/dev/mapper/") != "" ]] && bl_root=$ROOT_PART \
                      || bl_root=$"PARTUUID="$(blkid -s PARTUUID ${ROOT_PART} | sed 's/.*=//g' | sed 's/"//g')
    
                    # Create default config files. First the loader
                    echo -e "default  arch\ntimeout  10" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf 2>/tmp/.errlog
    
                    # Second, the kernel conf files
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && \
                      echo -e "title\tManjaro Linux\nlinux\t/vmlinuz-linux\ninitrd\t/initramfs-linux.img\noptions\troot=${bl_root} rw" \
                      > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch.conf
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && \
                      echo -e "title\tManjaro Linux LTS\nlinux\t/vmlinuz-linux-lts\ninitrd\t/initramfs-linux-lts.img\noptions\troot=${bl_root} rw" \
                      > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch-lts.conf
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && \
                      echo -e "title\tManjaro Linux Grsec\nlinux\t/vmlinuz-linux-grsec\ninitrd\t/initramfs-linux-grsec.img\noptions\troot=${bl_root} rw" \
                      > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch-grsec.conf
                    [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && \
                      echo -e "title\tManjaro Linux Zen\nlinux\t/vmlinuz-linux-zen\ninitrd\t/initramfs-linux-zen.img\noptions\troot=${bl_root} rw" \
                      > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch-zen.conf
    
                    # Finally, amend kernel conf files for LUKS and BTRFS
                    sysdconf=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch*.conf)
                    for i in ${sysdconf}; do
                        [[ $LUKS_DEV != "" ]] && sed -i "s~rw~$LUKS_DEV rw~g" ${i}
                    done
                    ;;
                *) install_base_menu
                    ;;
            esac
        fi
    }

    check_mount
    
    # Set the default PATH variable
    arch_chroot "PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/core_perl" 2>/tmp/.errlog
    check_for_error

    if [[ $SYSTEM == "BIOS" ]]; then
        bios_bootloader
    else
        uefi_bootloader
    fi
}

install_network_menu() {
    local PARENT="$FUNCNAME"
    
    # ntp not exactly wireless, but this menu is the best fit.
    install_wireless_packages() {
    
        WIRELESS_PACKAGES=""
        wireless_pkgs="dialog iw rp-pppoe wireless_tools wpa_actiond"

        for i in ${wireless_pkgs}; do
            WIRELESS_PACKAGES="${WIRELESS_PACKAGES} ${i} - on"
        done

        # If no wireless, uncheck wireless pkgs
        [[ $(lspci | grep -i "Network Controller") == "" ]] && WIRELESS_PACKAGES=$(echo $WIRELESS_PACKAGES | sed "s/ on/ off/g")

        DIALOG " $_InstNMMenuPkg " --checklist "$_InstNMMenuPkgBody\n\n$_UseSpaceBar" 0 0 13 \
          $WIRELESS_PACKAGES \
          "ufw" "-" off \
          "gufw" "-" off \
          "ntp" "-" off \
          "b43-fwcutter" "Broadcom 802.11b/g/n" off \
          "bluez-firmware" "Broadcom BCM203x / STLC2300 Bluetooth" off \
          "ipw2100-fw" "Intel PRO/Wireless 2100" off \
          "ipw2200-fw" "Intel PRO/Wireless 2200" off \
          "zd1211-firmware" "ZyDAS ZD1211(b) 802.11a/b/g USB WLAN" off 2>${PACKAGES}

        if [[ $(cat ${PACKAGES}) != "" ]]; then
            clear
            basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
            check_for_error
        fi
    }

    install_cups() {
        DIALOG " $_InstNMMenuCups " --checklist "$_InstCupsBody\n\n$_UseSpaceBar" 0 0 5 \
          "cups" "-" on \
          "cups-pdf" "-" off \
          "ghostscript" "-" on \
          "gsfonts" "-" on \
          "samba" "-" off 2>${PACKAGES}

        if [[ $(cat ${PACKAGES}) != "" ]]; then
            clear
            basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
            check_for_error

        if [[ $(cat ${PACKAGES} | grep "cups") != "" ]]; then
            DIALOG " $_InstNMMenuCups " --yesno "$_InstCupsQ" 0 0
            if [[ $? -eq 0 ]]; then
                # Add openrc support. If openrcbase was installed, the file /tmp/.openrc should exist.
                if [[ -e /tmp/.openrc ]]; then
                    #statements
                    arch_chroot "rc-update add cupsd default" 2>/tmp/.errlog
                else
                    arch_chroot "systemctl enable org.cups.cupsd.service" 2>/tmp/.errlog
                fi
                check_for_error
                DIALOG " $_InstNMMenuCups " --infobox "\n$_Done!\n\n" 0 0
                sleep 2
                fi
            fi
        fi
    }

    submenu 5
    DIALOG " $_InstNMMenuTitle " --default-item ${HIGHLIGHT_SUB} --menu "$_InstNMMenuBody" 0 0 5 \
      "1" "$_SeeWirelessDev" \
      "2" "$_InstNMMenuPkg" \
      "3" "$_InstNMMenuNM" \
      "4" "$_InstNMMenuCups" \
      "5" "$_Back" 2>${ANSWER}

    case $(cat ${ANSWER}) in
        "1") # Identify the Wireless Device
            lspci -k | grep -i -A 2 "network controller" > /tmp/.wireless
            if [[ $(cat /tmp/.wireless) != "" ]]; then
                DIALOG " $_WirelessShowTitle " --textbox /tmp/.wireless 0 0
            else
                DIALOG " $_WirelessShowTitle " --msgbox "$_WirelessErrBody" 7 30
            fi
            ;;
        "2") install_wireless_packages
            ;;
        "3") install_nm
            ;;
        "4") install_cups
            ;;
        *) main_menu_online
            ;;
    esac

    install_network_menu
}

# Install xorg and input drivers. Also copy the xkbmap configuration file created earlier to the installed system
install_xorg_input() {
    echo "" > ${PACKAGES}

    DIALOG " $_InstGrMenuDS " --checklist "$_InstGrMenuDSBody\n\n$_UseSpaceBar" 0 0 11 \
      "wayland" "-" off \
      "xorg-server" "-" on \
      "xorg-server-common" "-" off \
      "xorg-server-utils" "-" on \
      "xorg-xinit" "-" on \
      "xorg-server-xwayland" "-" off \
      "xf86-input-evdev" "-" off \
      "xf86-input-keyboard" "-" on \
      "xf86-input-libinput" "-" on \
      "xf86-input-mouse" "-" on \
      "xf86-input-synaptics" "-" off 2>${PACKAGES}

    clear
    # If at least one package, install.
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
        check_for_error
    fi

    # now copy across .xinitrc for all user accounts
    user_list=$(ls ${MOUNTPOINT}/home/ | sed "s/lost+found//")
    for i in ${user_list}; do
        [[ -e ${MOUNTPOINT}/home/$i/.xinitrc ]] || cp -f ${MOUNTPOINT}/etc/X11/xinit/xinitrc ${MOUNTPOINT}/home/$i/.xinitrc
        arch_chroot "chown -R ${i}:${i} /home/${i}"
    done

    SUB_MENU="install_vanilla_de_wm"
    HIGHLIGHT_SUB=1
    
    install_vanilla_de_wm        
}

setup_graphics_card() {
    # Save repetition
    install_intel() {
        sed -i 's/MODULES=""/MODULES="i915"/' ${MOUNTPOINT}/etc/mkinitcpio.conf

        # Intel microcode (Grub, Syslinux and systemd-boot).
        # Done as seperate if statements in case of multiple bootloaders.
        if [[ -e ${MOUNTPOINT}/boot/grub/grub.cfg ]]; then
            DIALOG " grub-mkconfig " --infobox "$_PlsWaitBody" 0 0
            sleep 1
            arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>>/tmp/.errlog
        fi
        # Syslinux
        [[ -e ${MOUNTPOINT}/boot/syslinux/syslinux.cfg ]] && sed -i "s/INITRD /&..\/intel-ucode.img,/g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

        # Systemd-boot
        if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf ]]; then
            update=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/*.conf)
            for i in ${upgate}; do
                sed -i '/linux \//a initrd \/intel-ucode.img' ${i}
            done
        fi
    }

    # Save repetition
    install_ati() {
        sed -i 's/MODULES=""/MODULES="radeon"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
    }

    # Main menu. Correct option for graphics card should be automatically highlighted.
    DIALOG " Choose video-driver to be installed " --radiolist "$_InstDEBody $_UseSpaceBar" 0 0 12 \
      $(mhwd -l | awk 'FNR>4 {print $1}' | awk 'NF' |awk '$0=$0" - off"')  2> /tmp/.driver
    
    clear
    arch_chroot "mhwd -i pci $(cat /tmp/.driver)" 2>/tmp/.errlog

    GRAPHIC_CARD=$(lspci | grep -i "vga" | sed 's/.*://' | sed 's/(.*//' | sed 's/^[ \t]*//')

    # All non-NVIDIA cards / virtualisation
    if [[ $(echo $GRAPHIC_CARD | grep -i 'intel\|lenovo') != "" ]]; then install_intel
        elif [[ $(echo $GRAPHIC_CARD | grep -i 'ati') != "" ]]; then install_ati
        elif [[ $(cat /tmp/.driver) == "video-nouveau" ]]; then sed -i 's/MODULES=""/MODULES="nouveau"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
    fi

    check_for_error

    install_graphics_menu
}

security_menu() {
    local PARENT="$FUNCNAME"

    submenu 4
    DIALOG " $_SecMenuTitle " --default-item ${HIGHLIGHT_SUB} \
      --menu "$_SecMenuBody" 0 0 4 \
      "1" "$_SecJournTitle" \
      "2" "$_SecCoreTitle" \
      "3" "$_SecKernTitle " \
      "4" "$_Back" 2>${ANSWER}

    HIGHLIGHT_SUB=$(cat ${ANSWER})
    case $(cat ${ANSWER}) in
        # systemd-journald
        "1") DIALOG " $_SecJournTitle " --menu "$_SecJournBody" 0 0 7 \
               "$_Edit" "/etc/systemd/journald.conf" \
               "10M" "SystemMaxUse=10M" \
               "20M" "SystemMaxUse=20M" \
               "50M" "SystemMaxUse=50M" \
               "100M" "SystemMaxUse=100M" \
               "200M" "SystemMaxUse=200M" \
               "$_Disable" "Storage=none" 2>${ANSWER}

             if [[ $(cat ${ANSWER}) != "" ]]; then
                 if [[ $(cat ${ANSWER}) == "$_Disable" ]]; then
                     sed -i "s/#Storage.*\|Storage.*/Storage=none/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                     sed -i "s/SystemMaxUse.*/#&/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                     DIALOG " $_SecJournTitle " --infobox "\n$_Done!\n\n" 0 0
                     sleep 2
                 elif [[ $(cat ${ANSWER}) == "$_Edit" ]]; then
                     nano ${MOUNTPOINT}/etc/systemd/journald.conf
                 else
                     sed -i "s/#SystemMaxUse.*\|SystemMaxUse.*/SystemMaxUse=$(cat ${ANSWER})/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                     sed -i "s/Storage.*/#&/g" ${MOUNTPOINT}/etc/systemd/journald.conf
                     DIALOG " $_SecJournTitle " --infobox "\n$_Done!\n\n" 0 0
                     sleep 2
                 fi
             fi
             ;;
        # core dump
        "2") DIALOG " $_SecCoreTitle " --menu "$_SecCoreBody" 0 0 2 \
             "$_Disable" "Storage=none" \
             "$_Edit" "/etc/systemd/coredump.conf" 2>${ANSWER}

             if [[ $(cat ${ANSWER}) == "$_Disable" ]]; then
                 sed -i "s/#Storage.*\|Storage.*/Storage=none/g" ${MOUNTPOINT}/etc/systemd/coredump.conf
                 DIALOG " $_SecCoreTitle " --infobox "\n$_Done!\n\n" 0 0
                 sleep 2
             elif [[ $(cat ${ANSWER}) == "$_Edit" ]]; then
                 nano ${MOUNTPOINT}/etc/systemd/coredump.conf
             fi
             ;;
        # Kernel log access
        "3") DIALOG " $_SecKernTitle " --menu "$_SecKernBody" 0 0 2 \
             "$_Disable" "kernel.dmesg_restrict = 1" \
             "$_Edit" "/etc/systemd/coredump.conf.d/custom.conf" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "$_Disable") echo "kernel.dmesg_restrict = 1" > ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf
                         DIALOG " $_SecKernTitle " --infobox "\n$_Done!\n\n" 0 0
                         sleep 2 ;;
            "$_Edit") [[ -e ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf ]] && nano ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf \
                      || DIALOG " $_SeeConfErrTitle " --msgbox "$_SeeConfErrBody1" 0 0 ;;
        esac
             ;;
        *) main_menu_online
             ;;
    esac

    security_menu
}