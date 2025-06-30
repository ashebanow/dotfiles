#!/usr/bin/env python3
"""
Tagged Package Filter - Enhanced package filtering using tag-based queries

This module provides a flexible tag-based filtering system for package management,
replacing the previous boolean flag approach with a rich, multi-dimensional tagging system.
"""

import re
from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, List, Optional, Union


class TagNamespace(Enum):
    """Recognized tag namespaces for filtering"""

    OS = "os"  # Operating system
    ARCH = "arch"  # Architecture
    DIST = "dist"  # Distribution
    DISTTYPE = "disttype"  # Distribution type (atomic/traditional)
    DE = "de"  # Desktop environment
    PM = "pm"  # Package manager
    CAT = "cat"  # Category
    ROLE = "role"  # Machine role
    PRIORITY = "priority"  # Installation priority
    SCOPE = "scope"  # Installation scope


@dataclass
class Tag:
    """Represents a parsed tag with namespace and value"""

    namespace: Optional[str]
    value: str

    @classmethod
    def parse(cls, tag_string: str) -> "Tag":
        """Parse a tag string into namespace and value"""
        if ":" in tag_string:
            parts = tag_string.split(":", 1)
            return cls(namespace=parts[0], value=parts[1])
        return cls(namespace=None, value=tag_string)

    def __str__(self) -> str:
        if self.namespace:
            return f"{self.namespace}:{self.value}"
        return self.value

    def matches(self, other: Union[str, "Tag"]) -> bool:
        """Check if this tag matches another tag or pattern"""
        if isinstance(other, str):
            other = Tag.parse(other)

        # Exact match
        if self.namespace == other.namespace and self.value == other.value:
            return True

        # Hierarchical match for package managers (e.g., pm:homebrew matches pm:homebrew:darwin)
        if self.namespace == other.namespace == "pm":
            # Check if one is a prefix of the other
            self_parts = self.value.split(":")
            other_parts = other.value.split(":")

            # pm:homebrew matches pm:homebrew:darwin
            if len(self_parts) < len(other_parts):
                return other_parts[: len(self_parts)] == self_parts
            # pm:homebrew:darwin matches pm:homebrew
            elif len(other_parts) < len(self_parts):
                return self_parts[: len(other_parts)] == other_parts

        return False


class TagExpression:
    """Represents a boolean expression of tags"""

    def __init__(self, expression: str):
        self.expression = expression.strip()
        self._tokens = self._tokenize(expression)

    def _tokenize(self, expression: str) -> List[str]:
        """Tokenize the expression into operators and tag strings"""
        # Simple tokenizer for AND, OR, NOT, parentheses
        pattern = r"(\(|\)|AND|OR|NOT|[^()\s]+)"
        tokens = re.findall(pattern, expression)
        return tokens

    def evaluate(self, tags: List[str]) -> bool:
        """Evaluate the expression against a list of tags"""
        tag_objects = [Tag.parse(t) for t in tags]
        return self._evaluate_tokens(self._tokens, tag_objects)

    def _evaluate_tokens(self, tokens: List[str], tags: List[Tag]) -> bool:
        """Recursive evaluation of tokenized expression"""
        if not tokens:
            return True

        # Handle single tag
        if len(tokens) == 1 and tokens[0] not in ("AND", "OR", "NOT", "(", ")"):
            query_tag = Tag.parse(tokens[0])
            return any(tag.matches(query_tag) for tag in tags)

        # Handle parentheses by finding matching pairs and evaluating contents
        if "(" in tokens:
            # Find the first opening parenthesis
            start = tokens.index("(")
            # Find the matching closing parenthesis
            depth = 0
            end = -1
            for i in range(start, len(tokens)):
                if tokens[i] == "(":
                    depth += 1
                elif tokens[i] == ")":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break

            if end > start:
                # Evaluate the parenthesized expression
                inner_result = self._evaluate_tokens(tokens[start + 1 : end], tags)
                # Replace the parenthesized part with the result and continue
                new_tokens = tokens[:start] + [str(inner_result)] + tokens[end + 1 :]
                return self._evaluate_tokens(new_tokens, tags)

        # Handle NOT
        if tokens[0] == "NOT":
            if len(tokens) > 1:
                return not self._evaluate_tokens(tokens[1:], tags)
            else:
                return True  # NOT with no operand is True

        # Handle AND/OR (find the operator with lowest precedence)
        # OR has lower precedence than AND
        or_indices = [i for i, t in enumerate(tokens) if t == "OR"]
        if or_indices:
            # Split on the first OR
            i = or_indices[0]
            left = self._evaluate_tokens(tokens[:i], tags)
            right = self._evaluate_tokens(tokens[i + 1 :], tags)
            return left or right

        and_indices = [i for i, t in enumerate(tokens) if t == "AND"]
        if and_indices:
            # Split on the first AND
            i = and_indices[0]
            left = self._evaluate_tokens(tokens[:i], tags)
            right = self._evaluate_tokens(tokens[i + 1 :], tags)
            return left and right

        # Handle special tokens
        if len(tokens) == 1:
            token = tokens[0]
            if token == "True":
                return True
            elif token == "False":
                return False
            else:
                # Treat as tag
                query_tag = Tag.parse(token)
                return any(tag.matches(query_tag) for tag in tags)

        # If we get here, we have multiple tokens with no operators
        # This shouldn't happen with proper tokenization, so default to False
        return False


class TaggedPackageFilter:
    """Enhanced package filtering using tag-based queries"""

    def __init__(self, toml_data: Dict[str, Any], platform_detector: Any):
        self.toml_data = toml_data
        self.platform = platform_detector
        self.platform_tags = self._get_platform_tags()

    def _get_platform_tags(self) -> List[str]:
        """Get tags representing the current platform"""
        tags = []

        # OS tags
        if self.platform.is_darwin:
            tags.append("os:macos")
        elif self.platform.is_linux:
            tags.append("os:linux")

        # Architecture tags (would need enhancement in PlatformDetector)
        # For now, assume x86_64 - this should be detected properly
        tags.append("arch:x86_64")

        # Distribution tags
        if hasattr(self.platform, "is_arch_like") and self.platform.is_arch_like:
            tags.append("dist:arch")
        if hasattr(self.platform, "is_debian_like") and self.platform.is_debian_like:
            tags.extend(["dist:debian", "dist:ubuntu"])
        if hasattr(self.platform, "is_fedora_like") and self.platform.is_fedora_like:
            tags.append("dist:fedora")

        # Package manager tags
        native_pm = self.platform.get_native_package_manager()
        if native_pm:
            tags.append(f"pm:{native_pm}")

        if self.platform.supports_homebrew():
            if self.platform.is_darwin:
                tags.extend(["pm:homebrew", "pm:homebrew:darwin"])
            elif self.platform.is_linux:
                tags.extend(["pm:homebrew", "pm:homebrew:linux"])

        if self.platform.supports_flatpak():
            tags.append("pm:flatpak")

        # Desktop environment tags (if platform supports DE detection)
        if hasattr(self.platform, "get_desktop_environment_tag"):
            de_tag = self.platform.get_desktop_environment_tag()
            if de_tag:
                tags.append(de_tag)

        # Distribution type tags (atomic vs traditional)
        if hasattr(self.platform, "get_distribution_type_tag"):
            disttype_tag = self.platform.get_distribution_type_tag()
            if disttype_tag:
                tags.append(disttype_tag)

        return tags

    def get_package_tags(self, package_name: str, entry: Dict[str, Any]) -> List[str]:
        """Get all tags for a package, including auto-generated ones"""
        tags = entry.get("tags", []).copy()

        # Auto-generate tags from legacy fields if not migrated yet
        if not tags:
            tags = self._generate_legacy_tags(entry)

        return tags

    def _generate_legacy_tags(self, entry: Dict[str, Any]) -> List[str]:
        """Generate tags from legacy platform fields"""
        tags = []

        # OS and package manager tags from package availability
        if entry.get("arch-pkg"):
            tags.extend(["os:linux", "dist:arch", "pm:pacman"])
        if entry.get("apt-pkg"):
            tags.extend(["os:linux", "dist:debian", "dist:ubuntu", "pm:apt"])
        if entry.get("fedora-pkg"):
            tags.extend(["os:linux", "dist:fedora", "pm:dnf"])
        if entry.get("flatpak-pkg"):
            tags.extend(["os:linux", "pm:flatpak"])

        # Homebrew support
        if entry.get("brew-supports-darwin"):
            tags.extend(["os:macos", "pm:homebrew", "pm:homebrew:darwin"])
        if entry.get("brew-supports-linux"):
            tags.extend(["os:linux", "pm:homebrew", "pm:homebrew:linux"])

        # Remove duplicates while preserving order
        seen = set()
        unique_tags = []
        for tag in tags:
            if tag not in seen:
                seen.add(tag)
                unique_tags.append(tag)

        return unique_tags

    def is_tag_set(self, package_name: str, tag: str) -> bool:
        """Check if a package has a specific tag"""
        entry = self.toml_data.get(package_name, {})
        package_tags = self.get_package_tags(package_name, entry)

        query_tag = Tag.parse(tag)
        package_tag_objects = [Tag.parse(t) for t in package_tags]

        return any(pt.matches(query_tag) for pt in package_tag_objects)

    def has_any_tags(self, package_name: str, tags: List[str]) -> bool:
        """Check if package has any of the specified tags"""
        return any(self.is_tag_set(package_name, tag) for tag in tags)

    def has_all_tags(self, package_name: str, tags: List[str]) -> bool:
        """Check if package has all specified tags"""
        return all(self.is_tag_set(package_name, tag) for tag in tags)

    def filter_by_tags(self, query: str) -> Dict[str, Any]:
        """Filter packages using tag query language"""
        expression = TagExpression(query)
        filtered = {}

        for package_name, entry in self.toml_data.items():
            package_tags = self.get_package_tags(package_name, entry)
            if expression.evaluate(package_tags):
                filtered[package_name] = entry

        return filtered

    def filter_by_current_platform(self) -> Dict[str, Any]:
        """Filter packages compatible with current platform"""
        filtered = {}

        for package_name, entry in self.toml_data.items():
            package_tags = self.get_package_tags(package_name, entry)
            package_tag_objects = [Tag.parse(t) for t in package_tags]

            # Check if package is compatible with current platform
            # A package is compatible if it has at least one matching OS and PM tag
            has_compatible_os = any(
                any(pt.matches(platform_tag) for pt in package_tag_objects)
                for platform_tag in self.platform_tags
                if platform_tag.startswith("os:")
            )

            has_compatible_pm = any(
                any(pt.matches(platform_tag) for pt in package_tag_objects)
                for platform_tag in self.platform_tags
                if platform_tag.startswith("pm:")
            )

            if has_compatible_os and has_compatible_pm:
                filtered[package_name] = entry

        return filtered

    def get_packages_for_role(self, role: str) -> Dict[str, Any]:
        """Get packages appropriate for specific machine role"""
        return self.filter_by_tags(f"role:{role}")

    def get_packages_by_category(self, category: str) -> Dict[str, Any]:
        """Get packages in specific category"""
        return self.filter_by_tags(f"cat:{category}")

    def get_packages_for_desktop_environment(self, de: str) -> Dict[str, Any]:
        """Get packages specific to a desktop environment"""
        return self.filter_by_tags(f"de:{de}")

    def get_packages_excluding_desktop_environments(self, exclude_des: List[str]) -> Dict[str, Any]:
        """Get packages that are NOT specific to any of the given desktop environments"""
        exclude_query = " OR ".join([f"de:{de}" for de in exclude_des])
        return self.filter_by_tags(f"NOT ({exclude_query})")

    def get_packages_for_atomic_distros(self) -> Dict[str, Any]:
        """Get packages suitable for atomic/immutable distributions"""
        # Focus on packages that work well on atomic distros:
        # - Homebrew packages (work everywhere)
        # - Flatpaks (containerized, safe)
        # - Custom installs that don't require package layering
        # Use a simpler query that avoids complex NOT expressions with parentheses
        return self.filter_by_tags("pm:homebrew OR pm:flatpak OR pm:custom")

    def get_packages_for_traditional_distros(self) -> Dict[str, Any]:
        """Get packages suitable for traditional mutable distributions"""
        return self.filter_by_tags("disttype:traditional OR NOT disttype:atomic")

    def get_filtered_packages(self, target: str) -> Dict[str, Any]:
        """Get packages filtered for specific target (backward compatibility)"""
        # Map legacy targets to tag queries
        target_queries = {
            "native": self._get_native_query(),
            "flatpak": "pm:flatpak",
            "homebrew": "pm:homebrew AND NOT pm:homebrew:darwin",  # Non-cask homebrew
            "homebrew-darwin": "pm:homebrew:darwin",  # Darwin-specific (casks)
            "custom": "pm:custom",
        }

        if target in target_queries:
            return self.filter_by_tags(target_queries[target])

        return {}

    def _get_native_query(self) -> str:
        """Get query for native package manager packages"""
        native_pm = self.platform.get_native_package_manager()
        if native_pm:
            return f"pm:{native_pm}"
        return ""

    def should_include_package(
        self,
        package_name: str,
        entry: Dict[str, Any],
        required_tags: List[str] = None,
        excluded_tags: List[str] = None,
    ) -> bool:
        """Determine if a package should be included based on tag criteria"""
        package_tags = self.get_package_tags(package_name, entry)

        # Check required tags
        if required_tags:
            if not all(self.is_tag_set(package_name, tag) for tag in required_tags):
                return False

        # Check excluded tags
        if excluded_tags:
            if any(self.is_tag_set(package_name, tag) for tag in excluded_tags):
                return False

        return True


def migrate_package_to_tags(entry: Dict[str, Any]) -> Dict[str, Any]:
    """Migrate a package entry from legacy format to tagged format"""
    # Don't modify if already has tags
    if "tags" in entry:
        return entry

    tags = []

    # OS and distribution tags
    if entry.get("arch-pkg"):
        tags.extend(["os:linux", "dist:arch", "pm:pacman"])
        if entry.get("arch-is-aur"):
            tags.append("cat:aur")  # Special category for AUR packages

    if entry.get("apt-pkg"):
        tags.extend(["os:linux", "dist:debian", "dist:ubuntu", "pm:apt"])

    if entry.get("fedora-pkg"):
        tags.extend(["os:linux", "dist:fedora", "pm:dnf"])

    if entry.get("flatpak-pkg"):
        tags.extend(["os:linux", "pm:flatpak"])
        if entry.get("prefer_flatpak"):
            tags.append("priority:flatpak")

    # Homebrew tags
    brew_tags = []
    if entry.get("brew-supports-darwin"):
        brew_tags.extend(["os:macos", "pm:homebrew:darwin"])
    if entry.get("brew-supports-linux"):
        brew_tags.extend(["os:linux", "pm:homebrew:linux"])

    # If both platforms supported, use general homebrew tag instead of platform-specific
    if entry.get("brew-supports-darwin") and entry.get("brew-supports-linux"):
        # Remove platform-specific tags and use general tag
        brew_tags = ["os:macos", "os:linux", "pm:homebrew"]

    tags.extend(brew_tags)

    if entry.get("brew-is-cask"):
        tags.append("cat:cask")

    # Custom installation
    if entry.get("custom-install"):
        tags.append("pm:custom")

    # Priority tags
    priority = entry.get("priority", "").lower()
    if priority == "override":
        tags.append("priority:essential")
    elif priority == "flatpak":
        tags.append("priority:flatpak")

    custom_priority = entry.get("custom-install-priority", "").lower()
    if custom_priority == "always":
        tags.append("priority:custom-always")
    elif custom_priority == "fallback":
        tags.append("priority:custom-fallback")

    # Remove duplicates while preserving order
    seen = set()
    unique_tags = []
    for tag in tags:
        if tag not in seen:
            seen.add(tag)
            unique_tags.append(tag)

    # Add tags to entry
    migrated_entry = entry.copy()
    migrated_entry["tags"] = unique_tags

    return migrated_entry


def auto_categorize_package(package_name: str, description: str) -> List[str]:
    """Automatically suggest category tags based on package metadata"""
    tags = []
    name_lower = package_name.lower()
    desc_lower = description.lower() if description else ""

    # Development tools
    dev_keywords = ["compiler", "debugger", "development", "programming", "sdk", "ide"]
    if any(keyword in name_lower or keyword in desc_lower for keyword in dev_keywords):
        tags.append("cat:development")

    # Version control
    if any(vcs in name_lower for vcs in ["git", "svn", "mercurial", "hg", "cvs"]):
        tags.append("cat:vcs")

    # Editors
    if any(editor in name_lower for editor in ["vim", "emacs", "nano", "editor", "nvim"]):
        tags.append("cat:editor")

    # Shells and terminals
    if any(term in name_lower for term in ["shell", "bash", "zsh", "fish", "terminal", "tmux"]):
        tags.append("cat:shell")
        tags.append("cat:terminal")

    # System tools
    if any(
        sys in name_lower or sys in desc_lower
        for sys in ["system", "monitor", "process", "cpu", "memory"]
    ):
        tags.append("cat:system")

    # Network tools
    if any(
        net in name_lower or net in desc_lower
        for net in ["network", "http", "ftp", "ssh", "vpn", "proxy"]
    ):
        tags.append("cat:network")

    # Security tools
    if any(
        sec in name_lower or sec in desc_lower
        for sec in ["security", "crypt", "password", "auth", "gpg"]
    ):
        tags.append("cat:security")

    # Multimedia
    if any(media in name_lower for media in ["video", "audio", "player", "ffmpeg", "vlc"]):
        tags.append("cat:multimedia")

    # Graphics
    if any(gfx in name_lower for gfx in ["image", "photo", "graphics", "draw", "gimp"]):
        tags.append("cat:graphics")

    # Database tools
    if any(db in name_lower for db in ["sql", "database", "postgres", "mysql", "mongo", "redis"]):
        tags.append("cat:database-tools")

    # Container/virtualization
    if any(
        virt in name_lower for virt in ["docker", "container", "kubernetes", "k8s", "vagrant", "vm"]
    ):
        tags.append("cat:virtualization")

    # File management
    if any(fm in name_lower for fm in ["file", "finder", "explorer", "ranger", "fzf"]):
        tags.append("cat:filesystem")

    # Communication
    if any(comm in name_lower for comm in ["chat", "irc", "slack", "discord", "telegram"]):
        tags.append("cat:communication")

    # Browsers
    if any(
        browser in name_lower for browser in ["firefox", "chrome", "chromium", "browser", "surf"]
    ):
        tags.append("cat:browser")

    # CLI tools (heuristic based on common patterns)
    if "-" in package_name or len(package_name) <= 4:
        tags.append("cat:cli-tool")

    # Desktop environment specific packages
    de_keywords = {
        "gnome": ["gnome", "gtk", "glib", "nautilus", "gdm"],
        "kde": ["kde", "plasma", "qt", "kwin", "dolphin"],
        "xfce": ["xfce", "xfce4", "thunar"],
        "hyprland": ["hyprland", "hypr"],
        "sway": ["sway", "waybar"],
        "i3": ["i3", "i3wm", "i3status", "i3blocks"],
        "niri": ["niri"],
        "awesome": ["awesome"],
        "qtile": ["qtile"],
        "dwm": ["dwm"],
        "bspwm": ["bspwm"],
        "openbox": ["openbox"],
    }

    for de, keywords in de_keywords.items():
        if any(keyword in name_lower or keyword in desc_lower for keyword in keywords):
            tags.append(f"de:{de}")
            break  # Only assign to one DE

    return tags
