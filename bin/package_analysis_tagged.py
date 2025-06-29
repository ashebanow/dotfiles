#!/usr/bin/env python3
"""
Enhanced Package Analysis with Auto-Tagging Support

This module extends package_analysis.py with automatic tag generation based on:
- Package names and descriptions
- Repology metadata
- Homebrew categories
- Platform availability
"""

import sys
import re
from pathlib import Path
from typing import Dict, Any, List, Set, Optional

# Add lib directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

try:
    from tagged_package_filter import auto_categorize_package, migrate_package_to_tags
except ImportError:
    print("Warning: tagged_package_filter not available")
    auto_categorize_package = None
    migrate_package_to_tags = None


def analyze_repology_data_for_tags(repology_data: Dict[str, Any]) -> List[str]:
    """Extract tags from Repology metadata"""
    tags = []
    
    if not repology_data:
        return tags
    
    # Analyze categories from different repositories
    categories_seen = set()
    for platform_data in repology_data.get('platforms', {}).values():
        if 'categories' in platform_data:
            categories_seen.update(platform_data['categories'])
    
    # Map Repology categories to our tags
    category_mapping = {
        'devel': 'cat:development',
        'development': 'cat:development',
        'editors': 'cat:editor',
        'vcs': 'cat:vcs',
        'net': 'cat:network',
        'network': 'cat:network',
        'www': 'cat:browser',
        'mail': 'cat:email',
        'multimedia': 'cat:multimedia',
        'audio': 'cat:audio',
        'video': 'cat:video',
        'graphics': 'cat:graphics',
        'games': 'cat:gaming',
        'security': 'cat:security',
        'sysutils': 'cat:system',
        'admin': 'cat:system',
        'database': 'cat:database-tools',
        'science': 'cat:data-science',
        'productivity': 'cat:productivity',
        'office': 'cat:office',
    }
    
    for category in categories_seen:
        cat_lower = category.lower()
        for key, tag in category_mapping.items():
            if key in cat_lower:
                tags.append(tag)
    
    # Analyze package availability for role tags
    platforms = repology_data.get('platforms', {})
    
    # If available on many platforms, likely a core tool
    if len(platforms) > 5:
        tags.append('priority:essential')
    
    # GUI vs CLI detection
    if any('gui' in str(v).lower() or 'gtk' in str(v).lower() or 'qt' in str(v).lower() 
           for v in platforms.values()):
        tags.append('cat:gui')
    
    return list(set(tags))  # Remove duplicates


def analyze_homebrew_data_for_tags(brew_data: Dict[str, Any]) -> List[str]:
    """Extract tags from Homebrew metadata"""
    tags = []
    
    if not brew_data:
        return tags
    
    # Check if it's a cask
    if brew_data.get('cask', False):
        tags.append('cat:cask')
        tags.append('role:desktop')  # Casks are typically desktop apps
    
    # Analyze Homebrew categories/tags
    brew_tags = brew_data.get('tags', [])
    brew_desc = brew_data.get('desc', '').lower()
    
    # Common patterns in Homebrew
    if 'command-line' in brew_desc or 'cli' in brew_desc:
        tags.append('cat:cli-tool')
    
    if 'terminal' in brew_desc:
        tags.append('cat:terminal')
    
    if 'development' in brew_desc or 'programming' in brew_desc:
        tags.append('cat:development')
    
    # Check dependencies for hints
    deps = brew_data.get('dependencies', [])
    if any('python' in dep for dep in deps):
        tags.append('cat:python')
    if any('node' in dep for dep in deps):
        tags.append('cat:javascript')
    
    return list(set(tags))


def suggest_role_tags(package_name: str, all_tags: List[str]) -> List[str]:
    """Suggest role tags based on package characteristics"""
    role_tags = []
    name_lower = package_name.lower()
    
    # Development tools
    dev_patterns = [
        'git', 'gcc', 'clang', 'python', 'node', 'rust', 'go', 'java',
        'vim', 'neovim', 'emacs', 'vscode', 'sublime', 'atom',
        'docker', 'vagrant', 'make', 'cmake', 'gradle', 'maven'
    ]
    if any(pattern in name_lower for pattern in dev_patterns) or 'cat:development' in all_tags:
        role_tags.append('role:development')
    
    # Server/headless tools
    server_patterns = [
        'nginx', 'apache', 'mysql', 'postgres', 'redis', 'elastic',
        'prometheus', 'grafana', 'systemd', 'cron', 'ssh'
    ]
    if any(pattern in name_lower for pattern in server_patterns) or 'cat:server' in all_tags:
        role_tags.append('role:server')
        role_tags.append('role:headless')
    
    # Desktop applications
    if 'cat:gui' in all_tags or 'cat:cask' in all_tags:
        role_tags.append('role:desktop')
    
    # Security tools
    security_patterns = ['gpg', 'ssh', 'vpn', 'firewall', 'antivirus', 'crypt']
    if any(pattern in name_lower for pattern in security_patterns) or 'cat:security' in all_tags:
        role_tags.append('role:security')
    
    # Data science tools
    ds_patterns = ['jupyter', 'pandas', 'numpy', 'scikit', 'tensorflow', 'torch']
    if any(pattern in name_lower for pattern in ds_patterns):
        role_tags.append('role:data-science')
    
    # Media/content creation
    media_patterns = ['ffmpeg', 'vlc', 'gimp', 'inkscape', 'blender', 'audacity']
    if any(pattern in name_lower for pattern in media_patterns) or 'cat:multimedia' in all_tags:
        role_tags.append('role:content-creation')
    
    # DevOps tools
    devops_patterns = ['ansible', 'terraform', 'kubernetes', 'k8s', 'helm', 'jenkins']
    if any(pattern in name_lower for pattern in devops_patterns):
        role_tags.append('role:devops')
    
    # Gaming
    if 'cat:gaming' in all_tags or 'game' in name_lower:
        role_tags.append('role:gaming')
    
    return list(set(role_tags))


def suggest_priority_tags(package_name: str, all_tags: List[str], 
                         platforms_count: int = 0) -> List[str]:
    """Suggest priority tags based on package characteristics"""
    priority_tags = []
    name_lower = package_name.lower()
    
    # Essential tools
    essential_patterns = [
        'git', 'vim', 'curl', 'wget', 'ssh', 'tmux', 'zsh', 'bash',
        'grep', 'sed', 'awk', 'find', 'make', 'gcc', 'python'
    ]
    if any(name_lower == pattern or name_lower.startswith(pattern + '-') 
           for pattern in essential_patterns):
        priority_tags.append('priority:essential')
        priority_tags.append('scope:core')
    
    # Recommended tools
    elif platforms_count > 3 or 'role:development' in all_tags:
        priority_tags.append('priority:recommended')
        priority_tags.append('scope:extended')
    
    # Optional tools
    else:
        priority_tags.append('priority:optional')
        priority_tags.append('scope:workflow-specific')
    
    return priority_tags


def generate_tags_for_package(package_name: str, entry: Dict[str, Any], 
                            repology_data: Optional[Dict[str, Any]] = None,
                            brew_data: Optional[Dict[str, Any]] = None) -> List[str]:
    """Generate comprehensive tags for a package"""
    tags = []
    
    # Start with any existing tags
    if 'tags' in entry:
        tags.extend(entry['tags'])
    
    # Auto-categorize based on name and description
    if auto_categorize_package:
        description = entry.get('description', '')
        suggested_cats = auto_categorize_package(package_name, description)
        tags.extend(suggested_cats)
    
    # Add tags from Repology data
    if repology_data:
        repology_tags = analyze_repology_data_for_tags(repology_data)
        tags.extend(repology_tags)
        
        # Platform count for priority
        platforms_count = len(repology_data.get('platforms', {}))
    else:
        platforms_count = 0
    
    # Add tags from Homebrew data
    if brew_data:
        brew_tags = analyze_homebrew_data_for_tags(brew_data)
        tags.extend(brew_tags)
    
    # Generate platform tags from package availability
    if migrate_package_to_tags:
        migrated_entry = migrate_package_to_tags(entry)
        tags.extend(migrated_entry.get('tags', []))
    
    # Suggest role tags
    role_tags = suggest_role_tags(package_name, tags)
    tags.extend(role_tags)
    
    # Suggest priority tags
    priority_tags = suggest_priority_tags(package_name, tags, platforms_count)
    tags.extend(priority_tags)
    
    # Architecture tags based on package characteristics
    if any(arch in package_name for arch in ['x86_64', 'amd64', '64']):
        tags.append('arch:x86_64')
    elif any(arch in package_name for arch in ['arm64', 'aarch64']):
        tags.append('arch:arm64')
    elif any(arch in package_name for arch in ['386', 'i686', '32']):
        tags.append('arch:x86')
    
    # Remove duplicates while preserving order
    seen = set()
    unique_tags = []
    for tag in tags:
        if tag not in seen and tag:  # Skip empty tags
            seen.add(tag)
            unique_tags.append(tag)
    
    return unique_tags


def enhance_package_entry_with_tags(package_name: str, entry: Dict[str, Any],
                                  repology_client: Any = None) -> Dict[str, Any]:
    """Enhance a package entry with auto-generated tags"""
    enhanced_entry = entry.copy()
    
    # Get additional data if available
    repology_data = None
    brew_data = None
    
    if repology_client and hasattr(repology_client, 'query_package'):
        try:
            repology_data = repology_client.query_package(package_name)
        except:
            pass
    
    # Generate tags
    tags = generate_tags_for_package(
        package_name, 
        enhanced_entry,
        repology_data=repology_data,
        brew_data=brew_data
    )
    
    # Add tags to entry
    enhanced_entry['tags'] = tags
    
    return enhanced_entry


def analyze_tags_distribution(toml_data: Dict[str, Any]) -> Dict[str, Any]:
    """Analyze the distribution of tags in the TOML data"""
    stats = {
        'total_packages': len(toml_data),
        'tagged_packages': 0,
        'tag_counts': {},
        'namespace_counts': {},
        'packages_by_role': {},
        'packages_by_category': {},
        'packages_by_priority': {}
    }
    
    for package_name, entry in toml_data.items():
        tags = entry.get('tags', [])
        if tags:
            stats['tagged_packages'] += 1
        
        for tag in tags:
            # Overall tag count
            stats['tag_counts'][tag] = stats['tag_counts'].get(tag, 0) + 1
            
            # Namespace count
            if ':' in tag:
                namespace = tag.split(':')[0]
                stats['namespace_counts'][namespace] = stats['namespace_counts'].get(namespace, 0) + 1
                
                # Specific categorizations
                if namespace == 'role':
                    role = tag.split(':')[1]
                    if role not in stats['packages_by_role']:
                        stats['packages_by_role'][role] = []
                    stats['packages_by_role'][role].append(package_name)
                
                elif namespace == 'cat':
                    category = tag.split(':')[1]
                    if category not in stats['packages_by_category']:
                        stats['packages_by_category'][category] = []
                    stats['packages_by_category'][category].append(package_name)
                
                elif namespace == 'priority':
                    priority = tag.split(':')[1]
                    if priority not in stats['packages_by_priority']:
                        stats['packages_by_priority'][priority] = []
                    stats['packages_by_priority'][priority].append(package_name)
    
    return stats


def print_tag_analysis(stats: Dict[str, Any]) -> None:
    """Print a formatted analysis of tag distribution"""
    print("\n=== Tag Distribution Analysis ===")
    print(f"Total packages: {stats['total_packages']}")
    print(f"Tagged packages: {stats['tagged_packages']} ({stats['tagged_packages']/stats['total_packages']*100:.1f}%)")
    
    print("\n=== Top Tags ===")
    sorted_tags = sorted(stats['tag_counts'].items(), key=lambda x: x[1], reverse=True)
    for tag, count in sorted_tags[:20]:
        print(f"{tag}: {count}")
    
    print("\n=== Namespace Distribution ===")
    for namespace, count in sorted(stats['namespace_counts'].items()):
        print(f"{namespace}: {count}")
    
    print("\n=== Packages by Role ===")
    for role, packages in sorted(stats['packages_by_role'].items()):
        print(f"{role}: {len(packages)} packages")
    
    print("\n=== Top Categories ===")
    sorted_cats = sorted(stats['packages_by_category'].items(), 
                        key=lambda x: len(x[1]), reverse=True)
    for category, packages in sorted_cats[:10]:
        print(f"{category}: {len(packages)} packages")
    
    print("\n=== Priority Distribution ===")
    for priority, packages in sorted(stats['packages_by_priority'].items()):
        print(f"{priority}: {len(packages)} packages")


# Example usage
if __name__ == '__main__':
    # Example of enhancing a package entry
    example_entry = {
        'arch-pkg': 'git',
        'apt-pkg': 'git',
        'brew-supports-darwin': True,
        'brew-supports-linux': True,
        'description': 'Distributed version control system'
    }
    
    enhanced = enhance_package_entry_with_tags('git', example_entry)
    print("Original entry:", example_entry)
    print("Enhanced entry:", enhanced)
    print("Generated tags:", enhanced['tags'])