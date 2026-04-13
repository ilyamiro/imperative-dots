#!/usr/bin/env bash

# ==============================================================================
# Function to select drivers, this is a experimental function
# ==============================================================================

manage_drivers() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Hardware Driver Configuration ===${RESET}"
        echo -e "${BOLD}${C_RED}=================== EXPERIMENTAL WARNING ===================${RESET}"
        echo -e "${C_RED}This automated driver installer is highly experimental and${RESET}"
        echo -e "${C_RED}can be unreliable across different kernel/distro variations.${RESET}"
        echo -e "${C_RED}It is strongly recommended to SKIP this and install your${RESET}"
        echo -e "${C_RED}graphics drivers manually according to your distro's wiki.${RESET}"
        echo -e "${BOLD}${C_RED}============================================================${RESET}\n"
        echo -e "Detected GPU Vendor: ${BOLD}${C_YELLOW}$GPU_VENDOR${RESET}\n"

        # Determine if a kernel driver is currently in use to prevent conflicts
        local current_driver="None"
        if command -v lsmod &> /dev/null; then
            if lsmod | grep -wq nvidia; then
                current_driver="nvidia"
            elif lsmod | grep -wq nouveau; then
                current_driver="nouveau"
            elif lsmod | grep -Ewq "amdgpu|radeon"; then
                current_driver="amd"
            elif lsmod | grep -Ewq "i915|xe"; then
                current_driver="intel"
            fi
        fi

        local options=""
        case "$GPU_VENDOR" in
            "NVIDIA")
                if [[ "$current_driver" == "nouveau" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Open-source 'nouveau' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Proprietary installation is locked out to prevent initramfs conflicts/black screens.${RESET}\n"
                    options="1. Update/Keep Nouveau (Open Source)\n2. Skip Driver Installation"
                elif [[ "$current_driver" == "nvidia" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Proprietary 'nvidia' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Open-source installation is locked out to prevent conflicts.${RESET}\n"
                    options="1. Update/Keep Proprietary NVIDIA Drivers\n2. Skip Driver Installation"
                else
                    options="1. Install Proprietary NVIDIA Drivers (Recommended for Gaming/Wayland)\n2. Install Nouveau (Open Source, Better VM compat)\n3. Skip Driver Installation"
                fi
                ;;
            "AMD")
                options="1. Install AMD Mesa & Vulkan Drivers (RADV)\n2. Skip Driver Installation"
                ;;
            "INTEL")
                options="1. Install Intel Mesa & Vulkan Drivers (ANV)\n2. Skip Driver Installation"
                ;;
            *)
                options="1. Install Generic Mesa Drivers (For VMs / Software Rendering)\n2. Skip Driver Installation"
                ;;
        esac

        local choice
        choice=$(echo -e "$options\nBack to Main Menu" | fzf \
            --ansi \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Drivers > " \
            --pointer=">" \
            --header=" Select the graphics drivers to install ")

        if [[ "$choice" == *"Back"* ]]; then break; fi

        # Require confirmation to INSTALL drivers, rather than skipping.
        if [[ "$choice" != *"Skip"* ]]; then
            echo -e "\n${BOLD}${C_RED}=================== ACTION REQUIRED ===================${RESET}"
            echo -e "${C_YELLOW}You have selected to AUTOMATICALLY install/configure drivers.${RESET}"
            echo -e "${C_YELLOW}If your system already has working drivers, this might break your boot sequence.${RESET}"
            echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed with this driver installation? (y/n): "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${C_RED}Driver setup aborted. Returning to menu...${RESET}"
                sleep 1.2
                continue
            fi
        fi

        # Strictly reset states before applying the verified configuration
        DRIVER_PKGS=()
        HAS_NVIDIA_PROPRIETARY=false

        if [[ "$choice" == *"Proprietary NVIDIA"* ]]; then
            DRIVER_CHOICE="NVIDIA Proprietary"
            HAS_NVIDIA_PROPRIETARY=true
            DRIVER_PKGS+=("nvidia-dkms" "nvidia-utils" "lib32-nvidia-utils" "linux-headers" "egl-wayland")
        
        elif [[ "$choice" == *"Nouveau"* ]]; then
            DRIVER_CHOICE="NVIDIA Nouveau"
            DRIVER_PKGS+=("mesa" "vulkan-nouveau" "lib32-mesa")

        elif [[ "$choice" == *"AMD"* ]]; then
            DRIVER_CHOICE="AMD Drivers"
            DRIVER_PKGS+=("mesa" "vulkan-radeon" "lib32-vulkan-radeon" "lib32-mesa" "xf86-video-amdgpu")

        elif [[ "$choice" == *"Intel"* ]]; then
            DRIVER_CHOICE="Intel Drivers"
            DRIVER_PKGS+=("mesa" "vulkan-intel" "lib32-vulkan-intel" "lib32-mesa" "intel-media-driver")

        elif [[ "$choice" == *"Generic"* ]]; then
            DRIVER_CHOICE="Generic / VM"
            DRIVER_PKGS+=("mesa" "lib32-mesa")

        elif [[ "$choice" == *"Skip"* ]]; then
            DRIVER_CHOICE="Skipped"
            DRIVER_PKGS=()
        fi

        echo -e "\n${C_GREEN}Driver configuration saved!${RESET}"
        sleep 1.2
        VISITED_DRIVERS=true
        break
    done
}