# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# make sure we only source this once.
if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    if [ -n "${sourced_system_environment:-}" ]; then
        return
    fi
    sourced_system_environment=true
fi

function check_platform_type {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        is_darwin=true
        # Fake the crucial variables from /etc/os-release
        ID="darwin"
    else
        source /etc/os-release

        if [[ $ID == "arch" || (-n $ID_LIKE && $ID_LIKE == "arch") ]]; then
            is_arch_like=true
            package_manager=yay
        fi

        if [[ $ID == "debian" || (-n $ID_LIKE && $ID_LIKE == "debian") ]]; then
            is_debian_like=true
            package_manager=apt
        fi

        if [[ $ID == "fedora" || (-n $ID_LIKE && $ID_LIKE == "fedora") ]]; then
            is_fedora_like=true
            if command -v dnf5; then
                package_manager=dnf5
            else
                package_manager=dnf
            fi
        fi
    fi

    # Check if running in virtualization (VM or container)
    if [[ "$is_darwin" == "true" ]]; then
        # macOS virtualization detection, courtesy of claude code....
        if [[ -n "${DOCKER_HOST:-}" ]] || \
           [[ -f /.dockerenv ]] || \
           [[ "$(sysctl -n machdep.cpu.features 2>/dev/null | grep -c VMM)" -gt 0 ]] || \
           [[ "$(ioreg -l | grep -c "VirtualBox\|VMware\|Parallels")" -gt 0 ]]; then
            is_virtualized=true
        fi
    else
        # Linux virtualization detection, courtesy of claude code....
        if [[ -f /.dockerenv ]] || \
           [[ -f /run/.containerenv ]] || \
           [[ -n "${container:-}" ]] || \
           [[ "$(systemd-detect-virt 2>/dev/null)" != "none" ]] || \
           [[ -d /proc/vz ]] || \
           [[ -f /proc/self/mountinfo ]] && grep -q "lxc\|docker" /proc/self/mountinfo 2>/dev/null || \
           [[ "$(grep -c "hypervisor\|docker\|lxc\|container" /proc/1/cgroup 2>/dev/null)" -gt 0 ]]; then
            is_virtualized=true
        fi
    fi
}

# platform identification variables
declare -x is_darwin=false
declare -x is_arch_like=false
declare -x is_debian_like=false
declare -x is_fedora_like=false
declare -x is_virtualized=false
declare -x package_manager=brew
check_platform_type