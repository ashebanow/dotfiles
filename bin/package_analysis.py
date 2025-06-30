#!/usr/bin/env -S uv run --script
"""
Clean package analysis tool for generating complete package mappings.

This tool treats Repology as the authoritative source and can:
1. Generate complete TOML mappings from package lists
2. Process specific packages for debugging
3. Validate roundtrip generation (TOML → package files → TOML)
4. Support custom package list files

Architecture: Repology-first → fallback to individual package managers → clean TOML generation
"""
# /// script
# dependencies = [
#   "requests",
#   "toml",
# ]
# ///

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Try to import dependencies
try:
    import requests

    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

try:
    import tomllib  # Python 3.11+

    def load_toml(filepath):
        try:
            with open(filepath, "rb") as f:
                return tomllib.load(f)
        except (FileNotFoundError, tomllib.TOMLDecodeError, OSError):
            return {}

except ImportError:
    try:
        import toml

        def load_toml(filepath):
            try:
                with open(filepath) as f:
                    return toml.load(f)
            except (FileNotFoundError, toml.TomlDecodeError, OSError):
                return {}

    except ImportError:

        def load_toml(filepath):
            raise ImportError("No TOML library available. Install with: pip install toml")


def _has_any_packages(entry: Dict[str, Any]) -> bool:
    """Check if a TOML entry has any packages found on any platform."""
    package_fields = ["arch-pkg", "apt-pkg", "fedora-pkg", "flatpak-pkg"]

    # Check if any package field has a non-empty value
    for field in package_fields:
        if entry.get(field, "").strip():
            return True

    # Check homebrew availability (indicated by brew-* fields)
    homebrew_fields = ["brew-supports-darwin", "brew-supports-linux", "brew-is-cask"]
    if any(entry.get(field) is not None for field in homebrew_fields):
        return True

    return False


def write_toml(data: Dict[str, Any], filepath: str) -> None:
    """Write data to TOML file with proper formatting and comments for empty entries."""
    with open(filepath, "w") as f:
        for section_name, section_data in sorted(data.items()):
            # Check if this entry has no packages found
            has_packages = _has_any_packages(section_data)

            if not has_packages:
                f.write(
                    f"# Package '{section_name}' not found on any platform - kept for periodic retry\n"
                )
                f.write("# This entry will be excluded from generated package files\n")

            # Quote section names that contain special characters
            if any(char in section_name for char in ["@", ".", "-", "/"]):
                f.write(f'["{section_name}"]\n')
            else:
                f.write(f"[{section_name}]\n")
            for key, value in sorted(section_data.items()):
                if isinstance(value, bool):
                    f.write(f"{key} = {str(value).lower()}\n")
                elif isinstance(value, str):
                    f.write(f'{key} = "{value}"\n')
                elif value is None:
                    f.write(f'{key} = ""\n')  # Convert None to empty string for TOML
                elif isinstance(value, dict) and key == "custom-install":
                    # Handle hierarchical custom install commands
                    f.write(f"\n[{section_name}.custom-install]\n")
                    for platform, commands in sorted(value.items()):
                        if isinstance(commands, list):
                            f.write(f"{platform} = [\n")
                            for cmd in commands:
                                f.write(f'  "{cmd}",\n')
                            f.write("]\n")
                        else:
                            f.write(f'{platform} = "{commands}"\n')
                elif isinstance(value, list):
                    # Handle arrays
                    f.write(f"{key} = [\n")
                    for item in value:
                        f.write(f'  "{item}",\n')
                    f.write("]\n")
                else:
                    f.write(f"{key} = {value}\n")
            f.write("\n")


class PackageListParser:
    """Parse different package list file formats."""

    @staticmethod
    def parse_brewfile(filepath: str) -> Set[str]:
        """Parse Brewfile and extract package names."""
        packages = set()
        if not os.path.exists(filepath):
            return packages

        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if line.startswith("brew "):
                    # Extract package name from brew "package-name"
                    match = re.search(r'brew\s+"([^"]+)"', line)
                    if match:
                        package = match.group(1)
                        # Remove tap prefix if present
                        if "/" in package:
                            package = package.split("/")[-1]
                        packages.add(package)
        return packages

    @staticmethod
    def parse_simple_list(filepath: str) -> Set[str]:
        """Parse simple package list (one package per line)."""
        packages = set()
        if not os.path.exists(filepath):
            return packages

        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    packages.add(line)
        return packages

    @classmethod
    def parse_file(cls, filepath: str) -> Set[str]:
        """Auto-detect file format and parse accordingly."""
        filename = os.path.basename(filepath).lower()

        if "brewfile" in filename:
            return cls.parse_brewfile(filepath)
        else:
            return cls.parse_simple_list(filepath)


class RepologyClient:
    """Client for querying Repology API with caching and rate limiting."""

    def __init__(self, cache_file: Optional[str] = "repology_cache.json", cache_ttl_days: int = 7):
        self.cache_file = cache_file
        self.cache = self._load_cache()
        self.rate_limit_delay = 3.0  # Very conservative: ~20 requests/minute
        self.cache_ttl_seconds = cache_ttl_days * 24 * 60 * 60  # Convert days to seconds
        self.headers = {
            "User-Agent": "dotfiles-package-manager/1.0 (https://github.com/ashebanow/dotfiles; contact: ashebanow@cattivi.com)"
        }
        self.name_mappings = self._load_name_mappings()
        self.package_aliases = self._load_package_aliases()

    def _load_cache(self) -> Dict[str, Any]:
        """Load cache from file."""
        if self.cache_file is None:
            return {}  # No file caching, use empty in-memory cache
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file) as f:
                    return json.load(f)
            except:
                return {}
        return {}

    def _save_cache(self) -> None:
        """Save cache to file."""
        if self.cache_file is None:
            return  # No file caching, skip save
        try:
            with open(self.cache_file, "w") as f:
                json.dump(self.cache, f, indent=2)
        except:
            pass  # Cache save failed, continue anyway

    def _load_package_aliases(self) -> Dict[str, List[str]]:
        """Load package aliases (alternative names for packages)."""
        return {
            # Package -> list of alternative names to also check
            "grimblast": ["grim", "grimshot"],  # grimblast is a wrapper around grim
            "python": ["python3"],
            "nodejs": ["node"],
            "neovim": ["nvim"],  # nvim is the command name for neovim
            "jj": ["jujutsu"],  # jj is an alias for jujutsu in Homebrew
        }

    def _score_repository(self, repo: str) -> int:
        """Score repository by currency and quality (higher is better)."""
        repo_lower = repo.lower()
        score = 0

        # Debian family scoring
        if "debian" in repo_lower:
            if "unstable" in repo_lower:
                score += 100  # Most current
            elif "testing" in repo_lower:
                score += 80
            elif "experimental" in repo_lower:
                score += 60  # Bleeding edge but not always stable
            elif "debian_13" in repo_lower or "trixie" in repo_lower:
                score += 85  # Current stable
            elif "debian_12" in repo_lower or "bookworm" in repo_lower:
                score += 70  # Previous stable
            elif "debian_11" in repo_lower or "bullseye" in repo_lower:
                score += 40  # Older stable
            else:
                score += 20  # Very old

        # Ubuntu family scoring
        elif "ubuntu" in repo_lower:
            if "24.04" in repo_lower or "24.10" in repo_lower:
                score += 90  # Current LTS/latest
            elif "22.04" in repo_lower:
                score += 80  # Previous LTS
            elif "20.04" in repo_lower:
                score += 60  # Older LTS
            else:
                score += 30  # Older releases

        # Fedora family scoring
        elif "fedora" in repo_lower:
            if "fedora_42" in repo_lower:
                score += 100  # Current release
            elif "fedora_41" in repo_lower:
                score += 85  # Previous release
            elif "fedora_40" in repo_lower:
                score += 70  # Older release
            else:
                score += 40  # Much older

        # Arch family scoring
        elif "arch" in repo_lower and "aur" not in repo_lower:
            score += 95  # Arch official repos are very current
        elif "aur" in repo_lower:
            score += 75  # AUR is current but community-maintained

        # Alpine scoring
        elif "alpine" in repo_lower:
            if "edge" in repo_lower:
                score += 90  # Most current
            elif "alpine_3_2" in repo_lower:  # Current stable (adjust as needed)
                score += 85
            else:
                score += 50  # Older alpine versions

        # RHEL/CentOS family
        elif any(distro in repo_lower for distro in ["almalinux", "centos", "rhel"]):
            if any(version in repo_lower for version in ["_9", "_10"]):
                score += 75  # Current enterprise releases
            elif "_8" in repo_lower:
                score += 60  # Previous enterprise release
            else:
                score += 30  # Older enterprise releases

        return score

    def _is_stable_version(self, version: str) -> bool:
        """Check if a version is stable (not beta/alpha/RC)."""
        version_lower = version.lower()

        # Check for development version patterns
        unstable_patterns = [
            "~a",
            "~b",
            "~rc",  # Debian-style
            "-alpha",
            "-beta",
            "-rc",  # Standard patterns
            ".dev",
            ".pre",  # Python development versions
            "-dev",
            "-devel",  # Development packages
            "git",
            "svn",  # VCS versions
            "snapshot",  # Snapshot builds
        ]

        return not any(pattern in version_lower for pattern in unstable_patterns)

    def _is_vulnerable_version(self, package_name: str, version: str) -> bool:
        """Check if a specific package version has known vulnerabilities."""
        package_lower = package_name.lower()

        # Known vulnerable versions
        vulnerable_versions = {
            "python": ["3.11.2"],  # Has security vulnerability as mentioned
            "python3": ["3.11.2"],
            "python311": ["3.11.2"],
            # Add more as needed
        }

        base_package = package_lower.replace("python3", "python")
        if base_package in vulnerable_versions:
            return version in vulnerable_versions[base_package]

        return False

    def _score_package_status(self, status: str) -> int:
        """Score package status from Repology (higher is better)."""
        if not status:
            return 0  # No status information

        status_lower = status.lower()

        # Status priority scoring
        if status_lower == "current":
            return 200  # Highest priority for current packages
        elif status_lower == "unique":
            return 150  # Good - only available in this repo
        elif status_lower == "rolling":
            return 100  # Good for rolling release distros
        elif status_lower == "newest":
            return 180  # Very good - newest version available
        elif status_lower == "outdated":
            return -100  # Penalty for outdated packages
        elif status_lower == "legacy":
            return -200  # Higher penalty for legacy packages
        elif status_lower == "incorrect":
            return -300  # High penalty for incorrect versions
        elif status_lower == "ignored":
            return -250  # High penalty for ignored packages
        else:
            # Unknown status - small penalty for uncertainty
            return -25

    def _load_name_mappings(self) -> Dict[str, str]:
        """Load package name mappings from file."""
        try:
            mappings_file = "package_name_mappings.json"
            if os.path.exists(mappings_file):
                with open(mappings_file) as f:
                    data = json.load(f)
                    return data.get("homebrew_to_repology", {})
        except:
            pass
        return {}

    def _resolve_repology_name(self, package_name: str) -> str:
        """Resolve package name to Repology project name."""
        return self.name_mappings.get(package_name, package_name)

    def _is_flatpak_application_id(self, package_name: str) -> bool:
        """Check if package name is a Flatpak application ID (reverse domain notation)."""
        # Must have dots and at least 2 components
        if "." not in package_name or len(package_name.split(".")) < 2:
            return False

        # Exclude Homebrew versioned packages (contain @)
        if "@" in package_name:
            return False

        # Exclude Homebrew tapped packages (contain /)
        if "/" in package_name:
            return False

        # Must start with known TLD patterns for Flatpak
        flatpak_tlds = {
            "org",
            "com",
            "app",
            "net",
            "io",
            "dev",
            "edu",
            "gov",
            "mil",
            "it",
            "us",
            "de",
            "uk",
        }
        first_part = package_name.split(".")[0].lower()
        return first_part in flatpak_tlds

    def _extract_project_name_from_flatpak_id(self, flatpak_id: str) -> str:
        """Extract upstream project name from Flatpak application ID using heuristics."""
        if not self._is_flatpak_application_id(flatpak_id):
            return flatpak_id

        parts = flatpak_id.split(".")

        # Generic suffixes to remove
        generic_suffixes = {"desktop", "client", "app", "application", "gui", "studio"}

        # Work backwards through parts to find meaningful name
        meaningful_parts = []
        for part in reversed(parts):
            part_lower = part.lower()
            # Skip generic suffixes and single letters
            if part_lower not in generic_suffixes and len(part) > 1:
                meaningful_parts.append(part_lower)

        if not meaningful_parts:
            # Fallback to last part if nothing meaningful found
            return parts[-1].lower()

        # Handle duplicate components (e.g., app.ytmdesktop.ytmdesktop)
        if len(meaningful_parts) >= 2 and meaningful_parts[0] == meaningful_parts[1]:
            return meaningful_parts[0]

        # Return the most specific (last meaningful) component
        return meaningful_parts[0]

    def _is_cache_expired(self, package_name: str) -> bool:
        """Check if cache entry is expired."""
        if package_name not in self.cache:
            return True

        cache_entry = self.cache[package_name]
        if not isinstance(cache_entry, dict) or "_timestamp" not in cache_entry:
            return True  # Old cache format, consider expired

        cache_time = cache_entry["_timestamp"]
        current_time = time.time()
        return (current_time - cache_time) > self.cache_ttl_seconds

    def query_package(self, package_name: str) -> Optional[Dict[str, Any]]:
        """Query Repology for package information."""
        if not REQUESTS_AVAILABLE:
            print(
                f"    Warning: requests library not available, skipping Repology query for {package_name}"
            )
            return None

        # Check cache first
        if package_name in self.cache and not self._is_cache_expired(package_name):
            cache_entry = self.cache[package_name]
            # Return the data without the timestamp
            if isinstance(cache_entry, dict) and "_timestamp" in cache_entry:
                return {k: v for k, v in cache_entry.items() if k != "_timestamp"}
            return cache_entry

        # Resolve package name to Repology project name
        repology_name = self._resolve_repology_name(package_name)
        if repology_name != package_name:
            print(
                f"\r\033[K🔄 Mapping {package_name} → {repology_name} for Repology...",
                end="",
                flush=True,
            )

        # Minimal feedback for API queries (overwritten by progress bar)
        print(f"\r\033[K🌐 Fetching {repology_name} from Repology API...", end="", flush=True)

        try:
            url = f"https://repology.org/api/v1/project/{repology_name}"
            response = requests.get(url, headers=self.headers, timeout=15)
            time.sleep(self.rate_limit_delay)

            if response.status_code == 200:
                data = response.json()
                result = self._parse_repology_response(data, package_name)

                # If Homebrew is available, get additional platform data
                if (
                    result
                    and isinstance(result, dict)
                    and result.get("platforms", {}).get("homebrew")
                ):
                    brew_data = BrewClient.query_package(package_name)
                    if brew_data:
                        result.update(
                            {
                                "brew-supports-linux": brew_data["supports_linux"],
                                "brew-supports-darwin": brew_data["supports_darwin"],
                                "brew-is-cask": brew_data["is_cask"],
                            }
                        )

                # Cache successful results
                cache_entry = result.copy() if isinstance(result, dict) else result
                if isinstance(cache_entry, dict):
                    cache_entry["_timestamp"] = time.time()
                else:
                    cache_entry = {"data": result, "_timestamp": time.time()}
                self.cache[package_name] = cache_entry
                self._save_cache()
                return result
            elif response.status_code == 404:
                # Cache negative results (package genuinely not found)
                self.cache[package_name] = {"_timestamp": time.time(), "data": None}
                self._save_cache()
                return None
            elif response.status_code == 403:
                print(
                    f"    Warning: Repology API rate limited (403) for {package_name} - will retry next time"
                )
                # Don't cache 403 errors - they should be retried
                return None
            else:
                print(
                    f"    Warning: Repology API error {response.status_code} for {package_name} - will retry next time"
                )
                # Don't cache server errors - they should be retried
                return None

        except Exception as e:
            print(f"    Warning: Repology query failed for {package_name}: {e}")
            return None

    def _score_package_name(self, target_name: str, candidate_name: str, repo: str) -> int:
        """Score a package name candidate for how well it matches the target.

        Higher scores are better matches.
        """
        if not candidate_name:
            return 0

        candidate_lower = candidate_name.lower()
        target_lower = target_name.lower()

        score = 0

        # Exact match gets highest score - much higher than any other factors
        if candidate_lower == target_lower:
            score += 5000

        # Exact match ignoring common prefixes/suffixes
        candidate_clean = (
            candidate_lower.replace("lib", "").replace("-dev", "").replace("-devel", "")
        )
        target_clean = target_lower.replace("lib", "").replace("-dev", "").replace("-devel", "")
        if candidate_clean == target_clean:
            score += 4500

        # Contains target name
        if target_lower in candidate_lower:
            score += 500

        # Special handling for versioned targets: boost exact base name matches
        if "@" in target_name:
            target_base_name = target_name.split("@")[0].lower()
            if candidate_lower == target_base_name:
                score += 6000  # Very high bonus for exact base name match in versioned targets

        # Note: Alias checking will be handled in _select_best_package_name
        # since we need access to the RepologyClient instance

        # Prefer shorter names (less likely to be variants)
        if len(candidate_name) <= len(target_name) + 3:
            score += 100

        # Penalty for unwanted suffixes
        bad_suffixes = [
            "-git",
            "-svn",
            "-bin",
            "-stable",
            "-latest",
            "-nightly",
            "-dev",
            "-devel",
            "-doc",
            "-docs",
        ]
        for suffix in bad_suffixes:
            if candidate_lower.endswith(suffix):
                score -= 200

        # Penalty for version numbers unless target has them
        import re

        if re.search(r"-\d+(\.\d+)*$", candidate_lower) and not re.search(
            r"-\d+(\.\d+)*$", target_lower
        ):
            score -= 250  # Increased penalty for version-specific packages

        # Penalty for architecture-specific packages
        arch_patterns = [
            "-m2",
            "-arm64",
            "-x86_64",
            "-i386",
            "-amd64",
            "avr-",
            "mingw-",
            "-arm-",
            "-none-eabi",
        ]
        for pattern in arch_patterns:
            if pattern in candidate_lower and pattern not in target_lower:
                score -= 300

        # Bonus for official repos over AUR
        if "aur" in repo:
            score -= 50
        elif "arch" in repo and "aur" not in repo:
            score += 50

        return score

    def _parse_version(self, package_name: str) -> tuple:
        """Parse version from package name, return (base_name, version_tuple).

        Examples:
        - gcc-13 -> ('gcc', (13,))
        - gcc-13.2 -> ('gcc', (13, 2))
        - python3.11 -> ('python', (3, 11))
        """
        import re

        # Pattern for version at end: package-X.Y.Z
        version_pattern = r"^(.+?)-(\d+(?:\.\d+)*)$"
        match = re.match(version_pattern, package_name)
        if match:
            base_name = match.group(1)
            version_str = match.group(2)
            version_parts = tuple(int(x) for x in version_str.split("."))
            return (base_name, version_parts)

        # Pattern for version in name: pythonX.Y
        embedded_pattern = r"^([a-zA-Z]+)(\d+(?:\.\d+)*)$"
        match = re.match(embedded_pattern, package_name)
        if match:
            base_name = match.group(1)
            version_str = match.group(2)
            version_parts = tuple(int(x) for x in version_str.split("."))
            return (base_name, version_parts)

        return (package_name, ())

    def _select_best_package_name(self, target_name: str, candidates: List[Dict[str, str]]) -> str:
        """Select the best package name from a list of candidates.

        candidates: List of dicts with 'name', 'repo', 'version' keys
        """
        if not candidates:
            return None

        # First, try to find exact or high-scoring matches
        scored_candidates = []
        for candidate in candidates:
            name = candidate.get("name", "")
            repo = candidate.get("repo", "")
            version = candidate.get("version", "")
            status = candidate.get("status", "")

            name_score = self._score_package_name(target_name, name, repo)
            repo_score = self._score_repository(repo)
            is_stable = self._is_stable_version(version)
            is_vulnerable = self._is_vulnerable_version(name, version)
            status_score = self._score_package_status(status)

            # Combine scores with stability, security, and status bonuses/penalties
            stability_score = 50 if is_stable else -100
            security_score = -500 if is_vulnerable else 0  # Heavy penalty for vulnerable versions
            total_score = name_score + repo_score + stability_score + security_score + status_score

            scored_candidates.append((total_score, name, repo, version, name_score, status))

        # Sort by total score (descending)
        scored_candidates.sort(reverse=True)

        # If we have a high-scoring match (exact or very close), use it
        best_total_score, best_name, best_repo, best_version, best_name_score, best_status = (
            scored_candidates[0]
        )
        if best_name_score >= 500:  # Good match threshold based on name matching
            return best_name

        # Parse target to check if it's a versioned package
        target_base, target_version = self._parse_version(target_name)

        # Collect all versioned candidates that match the base package name
        versioned_candidates = []
        for total_score, name, repo, version, name_score, status in scored_candidates:
            base_name, version_parts = self._parse_version(name)

            # Match against either the full target name or just the base name
            # Include versioned packages OR exact base name matches (even without versions)
            if (
                version_parts
                and (
                    base_name.lower() == target_name.lower()
                    or base_name.lower() == target_base.lower()
                )
            ) or (name.lower() == target_base.lower()):

                # For base name matches, give high priority to exact base name matches
                base_name_bonus = 0
                if base_name.lower() == target_base.lower():
                    base_name_bonus = 4000  # High bonus for exact base name match

                    # Extra bonus if the full package name exactly matches the base name
                    # This prioritizes "python" over "python-tests" when target is "python@3.11"
                    if name.lower() == target_base.lower():
                        base_name_bonus += 2000  # Even higher bonus for exact name = base name

                repo_score = self._score_repository(repo)
                is_stable = self._is_stable_version(version)
                is_vulnerable = self._is_vulnerable_version(name, version)
                status_score = self._score_package_status(status)

                versioned_candidates.append(
                    (
                        version_parts,
                        name,
                        repo,
                        version,
                        name_score + base_name_bonus,
                        repo_score,
                        is_stable,
                        is_vulnerable,
                        status,
                        status_score,
                    )
                )

        if versioned_candidates:
            if target_version:
                # For versioned targets (e.g., python@3.11), find best available version
                def enhanced_version_score(candidate):
                    """Calculate comprehensive score for version selection"""
                    (
                        version_parts,
                        name,
                        repo,
                        version,
                        name_score,
                        repo_score,
                        is_stable,
                        is_vulnerable,
                        status,
                        status_score,
                    ) = candidate

                    # Security first - heavily penalize vulnerable versions
                    if is_vulnerable:
                        return (-99999, 0, 0, 0, 0)  # Push vulnerable versions to bottom

                    # Calculate version distance
                    max_len = max(len(target_version), len(version_parts))
                    target_padded = target_version + (0,) * (max_len - len(target_version))
                    candidate_padded = version_parts + (0,) * (max_len - len(version_parts))

                    distance = sum(abs(t - c) for t, c in zip(target_padded, candidate_padded))

                    # Prefer versions >= target version (security-first approach)
                    version_preference = 0
                    if version_parts >= target_version:
                        version_preference = 100  # Bonus for newer/equal versions
                    else:
                        version_preference = -50  # Penalty for older versions

                    # Stability bonus
                    stability_bonus = 100 if is_stable else -200

                    # Total score: lower distance is better, higher other scores are better
                    # Use negative distance so higher scores are better overall
                    return (
                        -distance,
                        version_preference,
                        stability_bonus,
                        status_score,
                        repo_score,
                        name_score,
                    )

                # Sort by enhanced scoring (all descending due to negative distance)
                versioned_candidates.sort(key=enhanced_version_score, reverse=True)

                # Select best candidate, preferring non-git versions among equals
                best_candidates = []
                best_score = enhanced_version_score(versioned_candidates[0])

                for candidate in versioned_candidates:
                    if enhanced_version_score(candidate) == best_score:
                        best_candidates.append(candidate)
                    else:
                        break

                # Among equal candidates, prefer non-git versions
                for candidate in best_candidates:
                    (
                        version_parts,
                        name,
                        repo,
                        version,
                        name_score,
                        repo_score,
                        is_stable,
                        is_vulnerable,
                        status,
                        status_score,
                    ) = candidate
                    if not name.endswith("-git"):
                        return name

                # If all are git versions, return the first (best scored)
                return best_candidates[0][1]

            else:
                # For unversioned targets, select latest stable version from best repo
                def unversioned_score(candidate):
                    """Score for unversioned package selection"""
                    (
                        version_parts,
                        name,
                        repo,
                        version,
                        name_score,
                        repo_score,
                        is_stable,
                        is_vulnerable,
                        status,
                        status_score,
                    ) = candidate

                    # Security first
                    if is_vulnerable:
                        return ((-99999,), 0, 0, 0, 0)  # Push vulnerable versions to bottom

                    stability_bonus = 100 if is_stable else -200
                    return (version_parts, stability_bonus, status_score, repo_score, name_score)

                versioned_candidates.sort(key=unversioned_score, reverse=True)

                # Select best, preferring non-git versions
                latest_score = unversioned_score(versioned_candidates[0])
                for candidate in versioned_candidates:
                    if unversioned_score(candidate) == latest_score:
                        (
                            version_parts,
                            name,
                            repo,
                            version,
                            name_score,
                            repo_score,
                            is_stable,
                            is_vulnerable,
                            status,
                            status_score,
                        ) = candidate
                        if not name.endswith("-git"):
                            return name

                return versioned_candidates[0][1]

        # Fallback to highest scored candidate
        return scored_candidates[0][1]

    def _parse_repology_response(
        self, data: List[Dict[str, Any]], target_name: str
    ) -> Dict[str, Any]:
        """Parse Repology API response using smart package selection."""
        platforms = {
            "arch_official": False,
            "arch_aur": False,
            "debian": False,
            "ubuntu": False,
            "fedora": False,
            "homebrew": False,
            "flatpak": False,
        }

        # Collect candidates for each platform
        candidates = {"arch": [], "apt": [], "fedora": [], "flatpak": []}

        description = None
        description_priority = 0

        for entry in data:
            repo = entry.get("repo", "").lower()
            srcname = entry.get("srcname", "")
            binname = entry.get("binname", srcname)
            version = entry.get("version", "")
            entry_desc = entry.get("summary") or entry.get("description", "")

            # Description priority (higher = better)
            current_priority = 0
            if "homebrew" in repo or "brew" in repo:
                current_priority = 5
            elif "debian" in repo or "ubuntu" in repo:
                current_priority = 4
            elif "fedora" in repo:
                current_priority = 3
            elif "arch" in repo and "aur" not in repo:
                current_priority = 2
            elif "aur" in repo:
                current_priority = 1

            if entry_desc and current_priority > description_priority:
                description = entry_desc.strip()
                description_priority = current_priority

            # Collect candidates for each platform with version and status info
            package_name = binname or srcname
            status = entry.get("status", "")
            candidate_data = {
                "name": package_name,
                "repo": repo,
                "version": version,
                "status": status,
            }

            if "arch" in repo and "aur" not in repo:
                platforms["arch_official"] = True
                candidates["arch"].append(candidate_data)
            elif "aur" in repo:
                platforms["arch_aur"] = True
                candidates["arch"].append(candidate_data)
            elif "debian" in repo:
                platforms["debian"] = True
                candidates["apt"].append(candidate_data)
            elif "ubuntu" in repo:
                platforms["ubuntu"] = True
                candidates["apt"].append(candidate_data)
            elif "fedora" in repo:
                platforms["fedora"] = True
                candidates["fedora"].append(candidate_data)
            elif "homebrew" in repo or "brew" in repo:
                platforms["homebrew"] = True
            elif "flatpak" in repo or "flathub" in repo:
                platforms["flatpak"] = True
                candidates["flatpak"].append(candidate_data)

        # Select best package name for each platform
        package_names = {
            "arch": self._select_best_package_name(target_name, candidates["arch"]),
            "apt": self._select_best_package_name(target_name, candidates["apt"]),
            "fedora": self._select_best_package_name(target_name, candidates["fedora"]),
            "flatpak": self._select_best_package_name(target_name, candidates["flatpak"]),
        }

        return {"platforms": platforms, "package_names": package_names, "description": description}


class BrewClient:
    """Client for querying Homebrew."""

    @staticmethod
    def query_package(package_name: str) -> Optional[Dict[str, Any]]:
        """Query Homebrew for package information."""
        # Try formula first
        formula_result = BrewClient._query_formula(package_name)
        if formula_result:
            return formula_result

        # If formula fails, try cask
        cask_result = BrewClient._query_cask(package_name)
        if cask_result:
            return cask_result

        return None

    @staticmethod
    def _query_formula(package_name: str) -> Optional[Dict[str, Any]]:
        """Query Homebrew formula information."""
        try:
            result = subprocess.run(
                ["brew", "info", "--json", package_name], capture_output=True, text=True, timeout=10
            )

            if result.returncode != 0:
                return None

            data = json.loads(result.stdout)
            if not data:
                return None

            package_info = data[0]

            # Check platform support from bottle files
            bottle_files = package_info.get("bottle", {}).get("stable", {}).get("files", {})

            # Look for macOS platforms (any platform name containing macOS versions)
            macos_platforms = {
                "arm64_sequoia",
                "arm64_sonoma",
                "arm64_ventura",
                "arm64_monterey",
                "sonoma",
                "ventura",
                "monterey",
                "big_sur",
                "catalina",
            }
            supports_darwin = any(platform in macos_platforms for platform in bottle_files.keys())

            # Look for Linux platforms
            supports_linux = any("linux" in platform for platform in bottle_files.keys())

            return {
                "supports_darwin": supports_darwin,
                "supports_linux": supports_linux,
                "is_cask": False,  # This is a formula, not a cask
            }

        except Exception:
            return None

    @staticmethod
    def _query_cask(package_name: str) -> Optional[Dict[str, Any]]:
        """Query Homebrew cask information."""
        try:
            result = subprocess.run(
                ["brew", "info", "--json=v2", "--cask", package_name],
                capture_output=True,
                text=True,
                timeout=10,
            )

            if result.returncode != 0:
                return None

            data = json.loads(result.stdout)
            if not data or "casks" not in data or not data["casks"]:
                return None

            cask_info = data["casks"][0]

            # Casks are typically macOS-only
            # Check if there are any platform restrictions
            supported_platforms = cask_info.get("depends_on", {}).get("macos", {})

            # For casks, assume Darwin support unless explicitly restricted
            supports_darwin = True

            # Casks generally don't support Linux
            supports_linux = False

            return {
                "supports_darwin": supports_darwin,
                "supports_linux": supports_linux,
                "is_cask": True,  # This is a cask
            }

        except Exception:
            return None


def is_valid_package_name(package_name: str) -> bool:
    """Check if a package name is valid and not a phantom entry."""
    # Filter out obviously invalid package names that are likely parsing artifacts
    if not package_name or len(package_name.strip()) == 0:
        return False

    # Filter out single TLD components that are artifacts of Flatpak ID splitting
    invalid_prefixes = {"app", "com", "net", "org", "io", "dev", "edu", "gov", "mil"}
    if package_name.lower() in invalid_prefixes:
        return False

    # Allow all other package names (including full Flatpak IDs)
    return True


def collect_packages_from_lists(package_lists: List[str]) -> Set[str]:
    """Collect all packages from the specified package list files."""
    all_packages = set()

    for package_list in package_lists:
        if not os.path.exists(package_list):
            print(f"Warning: Package list file not found: {package_list}")
            continue

        packages = PackageListParser.parse_file(package_list)
        print(f"Found {len(packages)} packages in {package_list}")
        all_packages.update(packages)

    return all_packages


def generate_package_entry(
    package_name: str, repology_client: RepologyClient, existing_toml: Dict[str, Any]
) -> Tuple[str, Dict[str, Any]]:
    """Generate a complete TOML entry for a single package.

    Returns:
        Tuple of (key_name, entry_dict) where key_name is the proper TOML section name
        and entry_dict is the package data.
    """

    # Check if this is a Flatpak application ID and extract project name
    is_flatpak_id = repology_client._is_flatpak_application_id(package_name)
    brew_tap = None

    if is_flatpak_id:
        project_name = repology_client._extract_project_name_from_flatpak_id(package_name)
        print(f"    Detected Flatpak ID: {package_name} → {project_name}")
    elif "/" in package_name:
        # Handle Homebrew tapped packages
        parts = package_name.split("/")
        if len(parts) >= 2:
            brew_tap = "/".join(parts[:-1])  # Everything except the last part
            project_name = parts[-1]  # Just the package name
            print(f"    Detected tapped package: {package_name} → {project_name} (tap: {brew_tap})")
        else:
            project_name = package_name
    else:
        project_name = package_name

    # Start with base structure
    entry = {
        "arch-pkg": "",
        "apt-pkg": "",
        "fedora-pkg": "",
        "flatpak-pkg": package_name if is_flatpak_id else "",
        "brew-tap": brew_tap,
        "prefer_flatpak": is_flatpak_id,  # Auto-set based on source
        "priority": None,
        "description": f"TODO: Add description for {project_name}",
        "custom-install": "",  # Custom installation command
    }

    # Try Repology first using the extracted project name (authoritative source)
    repology_data = repology_client.query_package(project_name)

    # Check if Repology returned useful data
    has_repology_data = False
    if repology_data:
        platforms = repology_data["platforms"]
        pkg_names = repology_data["package_names"]

        # Check if any platforms or package names were found
        has_platforms = any(platforms.values())
        has_packages = any(pkg_names.values())
        has_repology_data = has_platforms or has_packages or repology_data.get("description")

        if has_repology_data:
            # Use Repology description if available
            if repology_data["description"]:
                entry["description"] = repology_data["description"]

            # Fill in package names
            if pkg_names["arch"]:
                entry["arch-pkg"] = pkg_names["arch"]
                entry["arch-is-aur"] = platforms["arch_aur"]

            if pkg_names["apt"]:
                entry["apt-pkg"] = pkg_names["apt"]

            if pkg_names["fedora"]:
                entry["fedora-pkg"] = pkg_names["fedora"]

            if pkg_names["flatpak"]:
                entry["flatpak-pkg"] = pkg_names["flatpak"]

            # Add Homebrew fields if it exists there
            if platforms["homebrew"]:
                brew_data = BrewClient.query_package(package_name)
                if brew_data:
                    entry.update(
                        {
                            "brew-supports-linux": brew_data["supports_linux"],
                            "brew-supports-darwin": brew_data["supports_darwin"],
                            "brew-is-cask": brew_data["is_cask"],
                        }
                    )
                else:
                    # Fallback defaults when Homebrew query fails (package doesn't exist)
                    entry.update(
                        {
                            "brew-supports-linux": False,
                            "brew-supports-darwin": False,  # Don't assume Darwin support if package doesn't exist
                            "brew-is-cask": False,
                        }
                    )

    # Try aliases if no useful Repology data found
    if not has_repology_data:
        aliases = repology_client.package_aliases.get(package_name, [])
        if aliases:
            print(f"    No Repology data for {package_name}, trying aliases: {', '.join(aliases)}")
            alias_results = []

            for alias in aliases:
                alias_data = repology_client.query_package(alias)
                if alias_data:
                    platforms = alias_data["platforms"]
                    pkg_names = alias_data["package_names"]
                    has_platforms = any(platforms.values())
                    has_packages = any(pkg_names.values())
                    has_useful_data = has_platforms or has_packages or alias_data.get("description")

                    if has_useful_data:
                        print(f"    Found useful data for alias '{alias}'")
                        alias_results.append((alias, alias_data))

            # Use the best alias result if we found any
            if alias_results:
                # Select the alias with the most complete data
                best_alias, repology_data = _select_best_alias_result(alias_results)
                print(f"    Using data from alias '{best_alias}'")

                # Process the alias data like we would original data
                platforms = repology_data["platforms"]
                pkg_names = repology_data["package_names"]
                has_repology_data = True  # Mark as found via alias

                # Use alias description if available
                if repology_data["description"]:
                    entry["description"] = repology_data["description"]

                # Fill in package names from alias
                if pkg_names["arch"]:
                    entry["arch-pkg"] = pkg_names["arch"]
                    entry["arch-is-aur"] = platforms["arch_aur"]

                if pkg_names["apt"]:
                    entry["apt-pkg"] = pkg_names["apt"]

                if pkg_names["fedora"]:
                    entry["fedora-pkg"] = pkg_names["fedora"]

                if pkg_names["flatpak"]:
                    entry["flatpak-pkg"] = pkg_names["flatpak"]

                # Add Homebrew fields if alias exists there
                if platforms["homebrew"]:
                    # Try original package name first, then alias name for Homebrew
                    brew_data = BrewClient.query_package(package_name)
                    if not brew_data:
                        brew_data = BrewClient.query_package(best_alias)

                    if brew_data:
                        entry.update(
                            {
                                "brew-supports-linux": brew_data["supports_linux"],
                                "brew-supports-darwin": brew_data["supports_darwin"],
                                "brew-is-cask": brew_data["is_cask"],
                            }
                        )
                    else:
                        # Fallback defaults when Homebrew query fails (package doesn't exist)
                        entry.update(
                            {
                                "brew-supports-linux": False,
                                "brew-supports-darwin": False,  # Don't assume Darwin support if package doesn't exist
                                "brew-is-cask": False,
                            }
                        )

    # Fallback: query Homebrew directly if no useful Repology data
    if not has_repology_data:
        print("    No useful Repology data, trying Homebrew...")
        # Use full package name with tap if available, otherwise project name
        brew_query_name = package_name if brew_tap else project_name
        brew_data = BrewClient.query_package(brew_query_name)

        # For Flatpak IDs, also try the original name as fallback
        if not brew_data and is_flatpak_id:
            brew_data = BrewClient.query_package(package_name)

        if brew_data:
            entry.update(
                {
                    "brew-supports-linux": brew_data["supports_linux"],
                    "brew-supports-darwin": brew_data["supports_darwin"],
                    "brew-is-cask": brew_data["is_cask"],
                }
            )

    # Merge with existing entry if available (preserve manual edits)
    # Check both the original package name and the extracted project name
    existing_entry = None
    if package_name in existing_toml:
        existing_entry = existing_toml[package_name]
    elif project_name in existing_toml:
        existing_entry = existing_toml[project_name]

    if existing_entry:
        # Preserve manually edited descriptions and other manual fields
        if existing_entry.get("description") and "TODO" not in existing_entry["description"]:
            entry["description"] = existing_entry["description"]
        # Preserve manual priority settings
        if existing_entry.get("priority"):
            entry["priority"] = existing_entry["priority"]
        # Preserve custom installation commands
        if existing_entry.get("custom-install"):
            entry["custom-install"] = existing_entry["custom-install"]

    return project_name, entry


def _select_best_alias_result(
    alias_results: List[Tuple[str, Dict[str, Any]]],
) -> Tuple[str, Dict[str, Any]]:
    """Select the best alias result from multiple successful alias queries.

    Prioritizes aliases with:
    1. More platforms supported
    2. More package names found
    3. Better quality description
    """
    if len(alias_results) == 1:
        return alias_results[0]

    def score_alias_result(alias_name: str, data: Dict[str, Any]) -> int:
        """Score an alias result for quality (higher is better)."""
        score = 0

        platforms = data.get("platforms", {})
        pkg_names = data.get("package_names", {})
        description = data.get("description", "")

        # Score based on number of platforms supported
        platform_count = sum(1 for supported in platforms.values() if supported)
        score += platform_count * 100

        # Score based on number of package names found
        package_count = sum(1 for name in pkg_names.values() if name and name.strip())
        score += package_count * 50

        # Score based on description quality
        if description and description.strip():
            if "TODO" not in description:
                score += 25  # Bonus for real description
            if len(description) > 50:
                score += 10  # Bonus for detailed description

        # Bonus for official repositories over AUR
        if pkg_names.get("arch") and not platforms.get("arch_aur", False):
            score += 20

        return score

    # Score all alias results
    scored_results = []
    for alias_name, data in alias_results:
        score = score_alias_result(alias_name, data)
        scored_results.append((score, alias_name, data))

    # Return the highest scoring alias
    scored_results.sort(reverse=True)
    return scored_results[0][1], scored_results[0][2]


def load_custom_installations(
    custom_install_path: str = "packages/custom_install.json",
) -> Dict[str, Any]:
    """Load custom installation configurations from JSON file."""
    if not os.path.exists(custom_install_path):
        return {}

    try:
        with open(custom_install_path) as f:
            data = json.load(f)
            return data.get("packages", {})
    except Exception as e:
        print(f"Warning: Failed to load custom installations from {custom_install_path}: {e}")
        return {}


def merge_custom_installation(
    entry: Dict[str, Any], package_name: str, custom_installs: Dict[str, Any]
) -> Dict[str, Any]:
    """Merge custom installation data into package entry."""
    if package_name not in custom_installs:
        return entry

    custom_data = custom_installs[package_name]

    # Add custom installation commands
    if "custom-install" in custom_data:
        entry["custom-install"] = custom_data["custom-install"]

    # Add custom installation priority (only if not default)
    priority = custom_data.get("custom-install-priority", "always")
    if priority != "always":
        entry["custom-install-priority"] = priority

    # Add other custom fields
    if "requires-confirmation" in custom_data:
        entry["requires-confirmation"] = custom_data["requires-confirmation"]

    if "install-condition" in custom_data:
        entry["install-condition"] = custom_data["install-condition"]

    # Update description if provided in custom data
    if "description" in custom_data and custom_data["description"]:
        entry["description"] = custom_data["description"]

    return entry


def generate_complete_toml(
    package_lists: List[str],
    specific_packages: List[str] = None,
    existing_toml_path: str = None,
    repology_cache: str = "repology_cache.json",
    custom_install_path: str = "packages/custom_install.json",
) -> Dict[str, Any]:
    """Generate complete TOML mappings from scratch."""

    # Load existing TOML for reference
    existing_toml = {}
    if existing_toml_path and os.path.exists(existing_toml_path):
        existing_toml = load_toml(existing_toml_path)
        print(f"Loaded {len(existing_toml)} existing entries from {existing_toml_path}")

    # Load custom installation configurations
    custom_installs = load_custom_installations(custom_install_path)
    if custom_installs:
        print(
            f"Loaded {len(custom_installs)} custom installation configs from {custom_install_path}"
        )

    # Collect packages to process
    if specific_packages:
        all_packages = set(specific_packages)
        print(f"Processing {len(all_packages)} specific packages")
    else:
        all_packages = collect_packages_from_lists(package_lists)
        # Add any packages from existing TOML that might not be in lists
        # Filter out invalid package names (phantom entries from previous broken runs)
        valid_existing_packages = {
            pkg for pkg in existing_toml.keys() if is_valid_package_name(pkg)
        }
        invalid_packages = set(existing_toml.keys()) - valid_existing_packages
        if invalid_packages:
            print(
                f"Filtering out {len(invalid_packages)} invalid packages: {', '.join(sorted(invalid_packages))}"
            )
        all_packages.update(valid_existing_packages)

        # Add packages from custom installations
        all_packages.update(custom_installs.keys())
        print(f"Processing {len(all_packages)} total packages")

    # Initialize clients
    repology_client = RepologyClient(repology_cache)

    # Generate entries
    complete_toml = {}

    for i, package_name in enumerate(sorted(all_packages), 1):
        # Progress indicator with spinner-like styling (clear line first)
        progress_bar = "▓" * (i * 20 // len(all_packages)) + "░" * (
            20 - (i * 20 // len(all_packages))
        )
        percent = (i * 100) // len(all_packages)
        print(
            f"\r\033[K🔍 [{progress_bar}] {percent:3d}% Analyzing package {i}/{len(all_packages)}: {package_name:<30}",
            end="",
            flush=True,
        )

        key_name, entry = generate_package_entry(package_name, repology_client, existing_toml)

        # Merge custom installation data
        entry = merge_custom_installation(entry, package_name, custom_installs)

        complete_toml[key_name] = entry

    # Clear progress line and show completion
    print(f"\r\033[K✅ [{'▓' * 20}] 100% Completed analysis of {len(all_packages)} packages")

    return complete_toml


def validate_roundtrip(toml_path: str, package_lists: List[str]) -> bool:
    """Validate roundtrip: package files → TOML → package files."""

    print("=== Roundtrip Validation ===")

    # Step 1: Generate TOML from original package files
    print("Step 1: Generating TOML from package files...")
    original_toml = generate_complete_toml(
        package_lists=package_lists,
        existing_toml_path=toml_path,
        repology_cache="validation_cache.json",
    )

    # Step 2: Generate package files from TOML
    print("Step 2: Generating package files from TOML...")

    # We need to import the generator functions
    sys.path.append(str(Path(__file__).parent))
    try:
        from package_generators import PackageFilter, PlatformDetector, generate_package_files

        # Create temporary TOML file
        temp_toml = "temp_validation.toml"
        write_toml(original_toml, temp_toml)

        try:
            generated_files = generate_package_files(
                toml_path=temp_toml, output_dir=None  # Don't write files, just get content
            )

            # Step 3: Parse generated files back to package sets
            print("Step 3: Parsing generated files...")
            generated_packages = {}

            for filename, content in generated_files.items():
                if filename == "Brewfile":
                    # Parse Brewfile content
                    packages = set()
                    for line in content.split("\n"):
                        line = line.strip()
                        if line.startswith("brew ") or line.startswith("cask "):
                            import re

                            match = re.search(r'(?:brew|cask)\s+"([^"]+)"', line)
                            if match:
                                package = match.group(1)
                                if "/" in package:
                                    package = package.split("/")[-1]
                                packages.add(package)
                    generated_packages["brewfile"] = packages
                else:
                    # Parse simple list files
                    packages = set()
                    for line in content.split("\n"):
                        line = line.strip()
                        if line and not line.startswith("#"):
                            # Remove AUR comments
                            if "  # AUR" in line:
                                line = line.replace("  # AUR", "")
                            packages.add(line.strip())
                    generated_packages[filename.lower()] = packages

            # Step 4: Compare original vs generated
            print("Step 4: Comparing original vs generated...")

            # Load original package files
            original_packages = {}
            for package_list in package_lists:
                if os.path.exists(package_list):
                    packages = PackageListParser.parse_file(package_list)
                    filename = os.path.basename(package_list).lower()
                    original_packages[filename] = packages

            # Compare results
            validation_passed = True

            for filename, original_set in original_packages.items():
                generated_set = generated_packages.get(filename, set())

                missing_in_generated = original_set - generated_set
                extra_in_generated = generated_set - original_set

                print(f"\n{filename}:")
                print(f"  Original: {len(original_set)} packages")
                print(f"  Generated: {len(generated_set)} packages")

                if missing_in_generated:
                    print(f"  Missing in generated: {sorted(missing_in_generated)}")
                    validation_passed = False

                if extra_in_generated:
                    print(f"  Extra in generated: {sorted(extra_in_generated)}")
                    # Extra packages might be OK (filtering can add packages)

                if not missing_in_generated and not extra_in_generated:
                    print("  ✓ Perfect match")

            print(f"\nValidation result: {'PASSED' if validation_passed else 'FAILED'}")
            return validation_passed

        finally:
            # Cleanup
            if os.path.exists(temp_toml):
                os.remove(temp_toml)
            if os.path.exists("validation_cache.json"):
                os.remove("validation_cache.json")

    except ImportError as e:
        print(f"Error: Cannot import package_generators: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate complete package mappings from package lists"
    )

    # Input options
    parser.add_argument(
        "--package-lists", nargs="+", help="Package list files to process (default: common files)"
    )
    parser.add_argument(
        "--package",
        nargs="+",
        dest="specific_packages",
        help="Process specific packages only (for debugging)",
    )
    parser.add_argument("--existing-toml", help="Path to existing TOML file for reference")

    # Output options
    parser.add_argument("--output", "-o", help="Write complete TOML to file")
    parser.add_argument(
        "--cache",
        default="repology_cache.json",
        help="Repology cache file (default: repology_cache.json)",
    )

    # Validation mode
    parser.add_argument("--validate", action="store_true", help="Validate roundtrip generation")

    args = parser.parse_args()

    # Get script directory for default paths
    script_dir = Path(__file__).parent
    dotfiles_dir = script_dir.parent

    # Set default package lists if none provided
    if not args.package_lists and not args.specific_packages:
        default_lists = [
            dotfiles_dir / "Brewfile.in",
            dotfiles_dir / "tests/assets/legacy_packages/Archfile",
            dotfiles_dir / "tests/assets/legacy_packages/Aptfile",
            dotfiles_dir / "tests/assets/legacy_packages/Flatfile",
        ]
        args.package_lists = [str(f) for f in default_lists if f.exists()]

    # Set default existing TOML if none provided
    if not args.existing_toml:
        default_toml = dotfiles_dir / "package_mappings.toml"
        if default_toml.exists():
            args.existing_toml = str(default_toml)

    # Set default custom install path
    custom_install_path = str(dotfiles_dir / "packages/custom_install.json")

    # Handle validation mode
    if args.validate:
        if not args.package_lists:
            print("Error: --validate requires --package-lists to be specified")
            sys.exit(1)

        validation_passed = validate_roundtrip(
            toml_path=args.existing_toml, package_lists=args.package_lists
        )
        sys.exit(0 if validation_passed else 1)

    print("=== Package Analysis Tool ===")
    print(f"Package lists: {args.package_lists or 'None'}")
    print(f"Specific packages: {args.specific_packages or 'None'}")
    print(f"Existing TOML: {args.existing_toml or 'None'}")
    print()

    # Generate complete TOML
    complete_toml = generate_complete_toml(
        package_lists=args.package_lists or [],
        specific_packages=args.specific_packages,
        existing_toml_path=args.existing_toml,
        repology_cache=args.cache,
        custom_install_path=custom_install_path,
    )

    # Output results
    if args.output:
        write_toml(complete_toml, args.output)
        print(f"\nComplete TOML written to: {args.output}")
    else:
        print(f"\nGenerated {len(complete_toml)} TOML entries:")
        print("=" * 50)
        for package_name, entry in sorted(complete_toml.items()):
            print(f"\n[{package_name}]")
            for key, value in entry.items():
                if value or value is False:
                    if isinstance(value, bool):
                        print(f"{key} = {str(value).lower()}")
                    else:
                        print(f'{key} = "{value}"')

    # Enhanced summary with timing and cache stats
    print("\n🎉 SUMMARY:")
    print(f"   📦 Generated {len(complete_toml)} complete package entries")
    if args.output:
        print(f"   💾 Output written to: {args.output}")
    print(f"   🗄️  Cache file: {args.cache}")

    # Show cache utilization if available
    if os.path.exists(args.cache):
        try:
            with open(args.cache) as f:
                cache_data = json.load(f)
            print(f"   📊 Cache entries: {len(cache_data)} packages cached")
        except:
            pass

    # Report empty mappings that need attention
    empty_mappings = []
    for pkg_name, data in complete_toml.items():
        # Check if the mapping is mostly empty (only has defaults or TODO descriptions)
        if (
            data.get("description", "").startswith("TODO:")
            or data.get("description", "") == ""
            or (not data.get("apt-pkg") and not data.get("arch-pkg") and not data.get("fedora-pkg"))
        ):
            empty_mappings.append(pkg_name)

    if empty_mappings:
        print("\n📝 EMPTY MAPPINGS REPORT:")
        print(f"   Found {len(empty_mappings)} packages with incomplete mappings:")
        print("   (Consider adding manual descriptions or checking package availability)")
        print()
        for pkg in sorted(empty_mappings):
            print(pkg)


if __name__ == "__main__":
    sys.exit(main())
