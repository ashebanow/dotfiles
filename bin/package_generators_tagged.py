#!/usr/bin/env -S uv run --script
"""
Enhanced Package File Generator with Tag-Based Filtering

This is an updated version of package_generators.py that integrates the new
TaggedPackageFilter for more flexible package management.
"""
# /// script
# dependencies = [
#   "toml",
# ]
# ///

import argparse
import os
import platform
import sys
from pathlib import Path
from typing import Any, Dict, Optional

# Add lib directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

try:
    from tagged_package_filter import TagExpression, TaggedPackageFilter
except ImportError:
    print("Error: tagged_package_filter module not found")
    print("Make sure lib/tagged_package_filter.py exists")
    sys.exit(1)

# Import TOML handling (same as original)
try:
    import tomllib  # Python 3.11+

    def load_toml(filepath):
        with open(filepath, "rb") as f:
            return tomllib.load(f)

except ImportError:
    try:
        import toml

        def load_toml(filepath):
            with open(filepath) as f:
                return toml.load(f)

    except ImportError:

        def load_toml(filepath):
            raise ImportError("No TOML library available. Install with: pip install toml")


class EnhancedPlatformDetector:
    """Enhanced platform detection with architecture support"""

    def __init__(self):
        self.system = platform.system()
        self.machine = platform.machine()
        self.is_darwin = self.system == "Darwin"
        self.is_linux = self.system == "Linux"

        # Architecture detection
        self.is_x86_64 = self.machine in ["x86_64", "AMD64"]
        self.is_arm64 = self.machine in ["arm64", "aarch64"]
        self.is_x86 = self.machine in ["i386", "i686"]

        # Distribution detection for Linux
        self.is_arch_like = False
        self.is_debian_like = False
        self.is_fedora_like = False
        self.is_atomic = False

        if self.is_linux:
            self._detect_linux_distribution()
            self._detect_atomic_distro()

    def _detect_linux_distribution(self):
        """Detect Linux distribution family"""
        try:
            with open("/etc/os-release") as f:
                os_release = f.read().lower()

                if "arch" in os_release:
                    self.is_arch_like = True
                elif any(distro in os_release for distro in ["debian", "ubuntu", "mint"]):
                    self.is_debian_like = True
                elif any(distro in os_release for distro in ["fedora", "rhel", "centos"]):
                    self.is_fedora_like = True
        except FileNotFoundError:
            pass

    def _detect_atomic_distro(self):
        """Detect if this is an atomic/immutable distribution"""
        # Check for atomic/immutable indicators
        atomic_indicators = [
            # Filesystem indicators
            "/usr/bin/rpm-ostree",  # rpm-ostree systems
            "/usr/bin/ostree",  # ostree-based systems
            "/run/ostree-booted",  # ostree booted indicator
            # Fedora Atomic variants
            "/usr/lib/rpm-ostree",
            # openSUSE MicroOS
            "/usr/bin/transactional-update",
            # Nix-based immutable systems
            "/nix/store",
        ]

        for indicator in atomic_indicators:
            if os.path.exists(indicator):
                self.is_atomic = True
                return

        # Check environment variables
        if os.environ.get("OSTREE_VERSION"):
            self.is_atomic = True
            return

        # Check for specific atomic distro names in os-release
        try:
            with open("/etc/os-release") as f:
                os_release = f.read().lower()
                atomic_names = [
                    "silverblue",
                    "kinoite",
                    "sericea",
                    "onyx",  # Fedora Atomic variants
                    "bazzite",
                    "bluefin",  # Universal Blue variants
                    "fedora atomic",
                    "fedora cosmic atomic",
                    "fedora sway atomic",
                    "microos",  # openSUSE MicroOS
                    "immutable",
                    "atomic",  # Generic indicators
                ]

                if any(name in os_release for name in atomic_names):
                    self.is_atomic = True
                    return

        except FileNotFoundError:
            pass

    def supports_homebrew(self) -> bool:
        """Check if platform supports Homebrew"""
        return self.is_darwin or (
            self.is_linux
            and (os.path.exists("/home/linuxbrew/.linuxbrew") or os.path.exists("/opt/homebrew"))
        )

    def supports_flatpak(self) -> bool:
        """Check if platform supports Flatpak"""
        return self.is_linux

    def get_native_package_manager(self) -> Optional[str]:
        """Get the native package manager for the platform"""
        if self.is_arch_like:
            return "pacman"
        elif self.is_debian_like:
            return "apt"
        elif self.is_fedora_like:
            return "dnf"
        elif self.is_darwin:
            return "homebrew"
        return None

    def get_architecture_tag(self) -> str:
        """Get architecture tag"""
        if self.is_x86_64:
            return "arch:x86_64"
        elif self.is_arm64:
            return "arch:arm64"
        elif self.is_x86:
            return "arch:x86"
        return f"arch:{self.machine}"

    def detect_desktop_environment(self) -> Optional[str]:
        """Detect the current desktop environment"""
        if not self.is_linux:
            return None

        # Check environment variables first
        desktop_session = os.environ.get("DESKTOP_SESSION", "").lower()
        xdg_current_desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
        gdmsession = os.environ.get("GDMSESSION", "").lower()

        # Check for specific DEs
        if any("gnome" in env for env in [desktop_session, xdg_current_desktop, gdmsession]):
            return "gnome"
        elif any(
            "kde" in env or "plasma" in env
            for env in [desktop_session, xdg_current_desktop, gdmsession]
        ):
            return "kde"
        elif any("xfce" in env for env in [desktop_session, xdg_current_desktop, gdmsession]):
            return "xfce"
        elif any("hyprland" in env for env in [desktop_session, xdg_current_desktop, gdmsession]):
            return "hyprland"
        elif any("sway" in env for env in [desktop_session, xdg_current_desktop, gdmsession]):
            return "sway"
        elif any("i3" in env for env in [desktop_session, xdg_current_desktop, gdmsession]):
            return "i3"
        elif any("niri" in env for env in [desktop_session, xdg_current_desktop, gdmsession]):
            return "niri"

        # Check for running processes as fallback
        try:
            import subprocess

            result = subprocess.run(
                ["pgrep", "-f"],
                capture_output=True,
                text=True,
                input="gnome-shell|plasmashell|xfce4-panel|Hyprland|sway|i3|niri",
            )
            if result.returncode == 0:
                processes = result.stdout.lower()
                if "gnome-shell" in processes:
                    return "gnome"
                elif "plasmashell" in processes:
                    return "kde"
                elif "xfce4-panel" in processes:
                    return "xfce"
                elif "hyprland" in processes:
                    return "hyprland"
                elif "sway" in processes:
                    return "sway"
                elif "i3" in processes:
                    return "i3"
                elif "niri" in processes:
                    return "niri"
        except:
            pass

        return None

    def get_desktop_environment_tag(self) -> Optional[str]:
        """Get desktop environment tag"""
        de = self.detect_desktop_environment()
        if de:
            return f"de:{de}"
        return None

    def get_distribution_type_tag(self) -> Optional[str]:
        """Get distribution type tag"""
        if not self.is_linux:
            return None

        if self.is_atomic:
            return "disttype:atomic"
        else:
            return "disttype:traditional"


class TaggedPackageFileGenerator:
    """Generate package files using tag-based filtering"""

    def __init__(self, toml_data: Dict[str, Any], platform_detector: EnhancedPlatformDetector):
        self.toml_data = toml_data
        self.platform = platform_detector
        self.filter = TaggedPackageFilter(toml_data, platform_detector)

    def generate_files_for_current_platform(self) -> Dict[str, str]:
        """Generate all applicable package files for the current platform"""
        files = {}

        # Native package manager files
        native_pm = self.platform.get_native_package_manager()
        if native_pm == "pacman":
            packages = self.filter.filter_by_tags("pm:pacman")
            if packages:
                files["Archfile"] = self._generate_archfile(packages)

        elif native_pm == "apt":
            packages = self.filter.filter_by_tags("pm:apt")
            if packages:
                files["Aptfile"] = self._generate_aptfile(packages)

        elif native_pm == "dnf":
            packages = self.filter.filter_by_tags("pm:dnf")
            if packages:
                files["Fedorafile"] = self._generate_fedorafile(packages)

        # Homebrew files
        if self.platform.supports_homebrew():
            if self.platform.is_darwin:
                # Regular packages
                brew_packages = self.filter.filter_by_tags("(pm:homebrew AND os:macos) AND NOT cat:cask AND NOT pm:homebrew:cask")
                if brew_packages:
                    files["Brewfile"] = self._generate_brewfile(brew_packages, include_casks=False)

                # Casks
                cask_packages = self.filter.filter_by_tags("pm:homebrew:cask OR (cat:cask AND os:macos)")
                if cask_packages:
                    files["Brewfile-darwin"] = self._generate_brewfile(
                        cask_packages, casks_only=True
                    )

            elif self.platform.is_linux:
                brew_packages = self.filter.filter_by_tags("pm:homebrew:linux")
                if brew_packages:
                    files["Brewfile"] = self._generate_brewfile(brew_packages)

        # Flatpak file
        if self.platform.supports_flatpak():
            flatpak_packages = self.filter.filter_by_tags("pm:flatpak")
            if flatpak_packages:
                files["Flatfile"] = self._generate_flatfile(flatpak_packages)

        # Custom installation file
        custom_packages = self.filter.filter_by_tags("pm:custom")
        if custom_packages:
            files["Customfile"] = self._generate_customfile(custom_packages)

        return files

    def generate_files_for_role(self, role: str) -> Dict[str, str]:
        """Generate package files for a specific machine role"""
        role_packages = self.filter.get_packages_for_role(role)
        files = {}

        # Group by package manager
        pm_groups = self._group_by_package_manager(role_packages)

        for pm, packages in pm_groups.items():
            if pm == "pacman":
                files["Archfile"] = self._generate_archfile(packages)
            elif pm == "apt":
                files["Aptfile"] = self._generate_aptfile(packages)
            elif pm == "homebrew":
                files["Brewfile"] = self._generate_brewfile(packages)
            elif pm == "flatpak":
                files["Flatfile"] = self._generate_flatfile(packages)
            elif pm == "custom":
                files["Customfile"] = self._generate_customfile(packages)

        return files

    def _generate_files_for_packages(self, packages: Dict[str, Any]) -> Dict[str, str]:
        """Generate package files for a specific set of packages"""
        files = {}

        # Group by package manager
        pm_groups = self._group_by_package_manager(packages)

        for pm, pm_packages in pm_groups.items():
            if pm == "pacman":
                files["Archfile"] = self._generate_archfile(pm_packages)
            elif pm == "apt":
                files["Aptfile"] = self._generate_aptfile(pm_packages)
            elif pm == "homebrew":
                files["Brewfile"] = self._generate_brewfile(pm_packages)
            elif pm == "flatpak":
                files["Flatfile"] = self._generate_flatfile(pm_packages)
            elif pm == "custom":
                files["Customfile"] = self._generate_customfile(pm_packages)

        return files

    def _group_by_package_manager(self, packages: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
        """Group packages by their package manager tags"""
        groups = {}

        for package_name, entry in packages.items():
            tags = self.filter.get_package_tags(package_name, entry)

            # Find package manager tags
            for tag in tags:
                if tag.startswith("pm:"):
                    pm = tag.split(":")[1]
                    if pm not in groups:
                        groups[pm] = {}
                    groups[pm][package_name] = entry

        return groups

    def _generate_brewfile(
        self, packages: Dict[str, Any], include_casks: bool = True, casks_only: bool = False
    ) -> str:
        """Generate Brewfile content"""
        lines = []
        
        # Add taps from Brewfile.in if this is the main Brewfile
        if not casks_only and Path("packages/Brewfile.in").exists():
            with open("packages/Brewfile.in", "r") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("tap "):
                        lines.append(line)
            if lines:
                lines.append("")

        if not casks_only:
            lines.append("# Homebrew packages")
            for package_name in sorted(packages.keys()):
                entry = packages[package_name]
                if not self.filter.is_tag_set(package_name, "cat:cask") and not self.filter.is_tag_set(package_name, "pm:homebrew:cask"):
                    brew_name = entry.get("brew-pkg", package_name)
                    lines.append(f'brew "{brew_name}"')

        if include_casks or casks_only:
            if lines and not casks_only:
                lines.append("")
            lines.append("# Homebrew casks")
            for package_name in sorted(packages.keys()):
                if self.filter.is_tag_set(package_name, "cat:cask") or self.filter.is_tag_set(package_name, "pm:homebrew:cask"):
                    entry = packages[package_name]
                    brew_name = entry.get("brew-pkg", package_name)
                    lines.append(f'cask "{brew_name}"')

        return "\n".join(lines) + "\n"

    def _generate_archfile(self, packages: Dict[str, Any]) -> str:
        """Generate Archfile content"""
        lines = ["# Arch packages"]

        for package_name in sorted(packages.keys()):
            entry = packages[package_name]
            arch_name = entry.get("arch-pkg", package_name)

            if self.filter.is_tag_set(package_name, "cat:aur"):
                lines.append(f"{arch_name}  # AUR")
            else:
                lines.append(arch_name)

        return "\n".join(lines) + "\n"

    def _generate_aptfile(self, packages: Dict[str, Any]) -> str:
        """Generate Aptfile content"""
        lines = ["# APT packages"]

        for package_name in sorted(packages.keys()):
            entry = packages[package_name]
            apt_name = entry.get("apt-pkg", package_name)
            lines.append(apt_name)

        return "\n".join(lines) + "\n"

    def _generate_fedorafile(self, packages: Dict[str, Any]) -> str:
        """Generate Fedora package file content"""
        lines = ["# DNF packages"]

        for package_name in sorted(packages.keys()):
            entry = packages[package_name]
            fedora_name = entry.get("fedora-pkg", package_name)
            lines.append(fedora_name)

        return "\n".join(lines) + "\n"

    def _generate_flatfile(self, packages: Dict[str, Any]) -> str:
        """Generate Flatpak file content"""
        lines = ["# Flatpak applications"]

        for package_name in sorted(packages.keys()):
            entry = packages[package_name]
            flatpak_id = entry.get("flatpak-pkg", "")
            if flatpak_id:
                lines.append(flatpak_id)

        return "\n".join(lines) + "\n"

    def _generate_customfile(self, packages: Dict[str, Any]) -> str:
        """Generate custom installation file"""
        from package_generators import PackageFileGenerator

        # Use existing custom file generation logic
        # but filtered by tags
        custom_commands = {}
        for package_name, entry in packages.items():
            if self.filter.is_tag_set(package_name, "pm:custom"):
                # Get platform-specific commands using existing logic
                generator = PackageFileGenerator()
                custom_install = entry.get("custom-install", "")
                if custom_install:
                    custom_commands[package_name] = entry

        if custom_commands:
            return generator.generate_customfile(custom_commands, self.toml_data)

        return ""


def main():
    parser = argparse.ArgumentParser(description="Generate package files using tag-based filtering")

    # Input/output options
    parser.add_argument("--toml", "-t", required=True, help="Path to package_mappings.toml file")
    parser.add_argument("--output-dir", "-o", help="Output directory for generated files")

    # Filtering options
    parser.add_argument(
        "--query",
        "-q",
        help='Tag query for filtering packages (e.g., "os:macos AND cat:development")',
    )
    parser.add_argument(
        "--role", help="Generate files for specific machine role (e.g., desktop, server)"
    )
    parser.add_argument(
        "--category", help="Generate files for specific category (e.g., development, multimedia)"
    )
    parser.add_argument(
        "--desktop-environment",
        "--de",
        help="Generate files for specific desktop environment (e.g., gnome, kde, hyprland)",
    )
    parser.add_argument(
        "--exclude-desktop-environments",
        "--exclude-de",
        nargs="+",
        help="Exclude packages for specific desktop environments",
    )
    parser.add_argument(
        "--atomic-distro",
        action="store_true",
        help="Generate files optimized for atomic/immutable distributions",
    )
    parser.add_argument(
        "--traditional-distro",
        action="store_true",
        help="Generate files for traditional mutable distributions",
    )

    # Output options
    parser.add_argument(
        "--print-only",
        "-p",
        action="store_true",
        help="Print generated files to stdout instead of writing",
    )
    parser.add_argument(
        "--list-tags", action="store_true", help="List all unique tags in the TOML file"
    )
    parser.add_argument(
        "--analyze", action="store_true", help="Analyze package distribution by tags"
    )

    args = parser.parse_args()

    # Load TOML data
    try:
        toml_data: Dict[str, Any] = load_toml(args.toml)
    except Exception as e:
        print(f"Error loading TOML file: {e}")
        return 1

    # Initialize platform detector and generator
    platform_detector = EnhancedPlatformDetector()
    generator = TaggedPackageFileGenerator(toml_data, platform_detector)

    # List tags mode
    if args.list_tags:
        all_tags = set()
        for package_name, entry in toml_data.items():
            tags = generator.filter.get_package_tags(package_name, entry)
            all_tags.update(tags)

        print("=== All Tags ===")
        for namespace in [
            "os",
            "arch",
            "dist",
            "disttype",
            "de",
            "pm",
            "cat",
            "role",
            "priority",
            "scope",
        ]:
            namespace_tags = sorted([t for t in all_tags if t.startswith(f"{namespace}:")])
            if namespace_tags:
                print(f"\n{namespace.upper()}:")
                for tag in namespace_tags:
                    print(f"  {tag}")

        # Custom tags without namespace
        custom_tags = sorted([t for t in all_tags if ":" not in t])
        if custom_tags:
            print("\nCUSTOM:")
            for tag in custom_tags:
                print(f"  {tag}")

        return 0

    # Analyze mode
    if args.analyze:
        print("=== Package Distribution Analysis ===")
        print(f"Total packages: {len(toml_data)}")

        # Analyze by namespace
        tag_counts = {}
        for package_name, entry in toml_data.items():
            tags = generator.filter.get_package_tags(package_name, entry)
            for tag in tags:
                tag_counts[tag] = tag_counts.get(tag, 0) + 1

        # Group by namespace
        namespaces = {}
        for tag, count in tag_counts.items():
            namespace = tag.split(":")[0] if ":" in tag else "custom"
            if namespace not in namespaces:
                namespaces[namespace] = []
            namespaces[namespace].append((tag, count))

        # Print by namespace
        for namespace in sorted(namespaces.keys()):
            print(f"\n{namespace.upper()}:")
            for tag, count in sorted(namespaces[namespace], key=lambda x: x[1], reverse=True):
                print(f"  {tag}: {count}")

        return 0

    # Generate files
    if args.query:
        # Filter by query
        filtered_packages = generator.filter.filter_by_tags(args.query)
        files = generator._generate_files_for_packages(filtered_packages)
    elif args.role:
        # Filter by role
        files = generator.generate_files_for_role(args.role)
    elif args.category:
        # Filter by category
        filtered_packages = generator.filter.get_packages_by_category(args.category)
        files = generator._generate_files_for_packages(filtered_packages)
    elif args.desktop_environment:
        # Filter by desktop environment
        filtered_packages = generator.filter.get_packages_for_desktop_environment(
            args.desktop_environment
        )
        files = generator._generate_files_for_packages(filtered_packages)
    elif args.exclude_desktop_environments:
        # Filter excluding desktop environments
        filtered_packages = generator.filter.get_packages_excluding_desktop_environments(
            args.exclude_desktop_environments
        )
        files = generator._generate_files_for_packages(filtered_packages)
    elif args.atomic_distro:
        # Filter for atomic/immutable distributions
        filtered_packages = generator.filter.get_packages_for_atomic_distros()
        files = generator._generate_files_for_packages(filtered_packages)
    elif args.traditional_distro:
        # Filter for traditional distributions
        filtered_packages = generator.filter.get_packages_for_traditional_distros()
        files = generator._generate_files_for_packages(filtered_packages)
    else:
        # Generate for current platform
        files = generator.generate_files_for_current_platform()

    # Output files
    if args.print_only:
        for filename, content in files.items():
            print(f"\n=== {filename} ===")
            print(content)
    else:
        output_dir = Path(args.output_dir) if args.output_dir else Path.cwd()
        output_dir.mkdir(parents=True, exist_ok=True)

        for filename, content in files.items():
            output_path = output_dir / filename
            with open(output_path, "w") as f:
                f.write(content)
            print(f"Generated: {output_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
