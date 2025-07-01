#!/usr/bin/env python3
"""
Tag Cache Utilities

Provides caching functionality for computed package tags to improve performance.
"""

import json
import time
from pathlib import Path
from typing import Dict, List, Optional, Any


class TagCache:
    """Manages cached tags for packages."""
    
    def __init__(self, cache_file: str = "tag_cache.json", ttl_days: int = 7):
        self.cache_file = cache_file
        self.ttl_seconds = ttl_days * 24 * 60 * 60
        self.cache = self._load_cache()
        self.modified = False
    
    def _load_cache(self) -> Dict[str, Any]:
        """Load cache from file."""
        if Path(self.cache_file).exists():
            try:
                with open(self.cache_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Warning: Could not load tag cache: {e}")
        return {}
    
    def save(self) -> None:
        """Save cache to file if modified."""
        if self.modified:
            try:
                with open(self.cache_file, 'w') as f:
                    json.dump(self.cache, f, indent=2, sort_keys=True)
                self.modified = False
            except Exception as e:
                print(f"Error saving tag cache: {e}")
    
    def get_tags(self, package_name: str, repology_timestamp: Optional[float] = None) -> Optional[List[str]]:
        """
        Get cached tags for a package if still fresh.
        
        Args:
            package_name: Name of the package
            repology_timestamp: Timestamp of the Repology data (to detect if source data changed)
        
        Returns:
            List of tags if cache is fresh, None otherwise
        """
        if package_name not in self.cache:
            return None
        
        entry = self.cache[package_name]
        current_time = time.time()
        
        # Check if cache entry is too old
        if current_time - entry.get('_timestamp', 0) > self.ttl_seconds:
            return None
        
        # Check if Repology data is newer than our cache
        if repology_timestamp and repology_timestamp > entry.get('_repology_timestamp', 0):
            return None
        
        return entry.get('tags', [])
    
    def set_tags(self, package_name: str, tags: List[str], repology_timestamp: Optional[float] = None) -> None:
        """
        Cache tags for a package.
        
        Args:
            package_name: Name of the package
            tags: List of tags to cache
            repology_timestamp: Timestamp of the Repology data used
        """
        self.cache[package_name] = {
            'tags': tags,
            '_timestamp': time.time(),
            '_repology_timestamp': repology_timestamp or 0
        }
        self.modified = True
    
    def invalidate(self, package_name: str) -> None:
        """Remove a package from the cache."""
        if package_name in self.cache:
            del self.cache[package_name]
            self.modified = True
    
    def invalidate_stale(self) -> int:
        """Remove all stale entries from cache. Returns count of removed entries."""
        current_time = time.time()
        stale_packages = []
        
        for package_name, entry in self.cache.items():
            if current_time - entry.get('_timestamp', 0) > self.ttl_seconds:
                stale_packages.append(package_name)
        
        for package_name in stale_packages:
            del self.cache[package_name]
        
        if stale_packages:
            self.modified = True
        
        return len(stale_packages)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics."""
        current_time = time.time()
        total_entries = len(self.cache)
        fresh_count = 0
        stale_count = 0
        
        for entry in self.cache.values():
            if current_time - entry.get('_timestamp', 0) <= self.ttl_seconds:
                fresh_count += 1
            else:
                stale_count += 1
        
        return {
            'total_entries': total_entries,
            'fresh_entries': fresh_count,
            'stale_entries': stale_count,
            'cache_file': self.cache_file,
            'ttl_days': self.ttl_seconds / (24 * 60 * 60)
        }


def merge_tag_caches(primary_cache: str, secondary_cache: str, output_cache: str) -> None:
    """
    Merge two tag cache files, preferring entries from primary cache.
    
    Args:
        primary_cache: Path to primary cache file (takes precedence)
        secondary_cache: Path to secondary cache file
        output_cache: Path to output cache file
    """
    primary = TagCache(primary_cache)
    secondary = TagCache(secondary_cache)
    output = TagCache(output_cache)
    
    # Start with all entries from secondary
    output.cache = secondary.cache.copy()
    
    # Override with entries from primary
    output.cache.update(primary.cache)
    
    output.modified = True
    output.save()
    
    print(f"Merged {len(primary.cache)} primary + {len(secondary.cache)} secondary = {len(output.cache)} total entries")


if __name__ == "__main__":
    # Simple CLI for cache management
    import argparse
    
    parser = argparse.ArgumentParser(description="Tag cache management utilities")
    parser.add_argument('command', choices=['stats', 'clean', 'merge'],
                        help='Command to execute')
    parser.add_argument('--cache', default='tag_cache.json',
                        help='Cache file path')
    parser.add_argument('--secondary', help='Secondary cache for merge')
    parser.add_argument('--output', help='Output cache for merge')
    
    args = parser.parse_args()
    
    if args.command == 'stats':
        cache = TagCache(args.cache)
        stats = cache.get_stats()
        print(f"Tag Cache Statistics:")
        print(f"  Total entries: {stats['total_entries']}")
        print(f"  Fresh entries: {stats['fresh_entries']}")
        print(f"  Stale entries: {stats['stale_entries']}")
        print(f"  TTL: {stats['ttl_days']} days")
        print(f"  File: {stats['cache_file']}")
    
    elif args.command == 'clean':
        cache = TagCache(args.cache)
        removed = cache.invalidate_stale()
        cache.save()
        print(f"Removed {removed} stale entries from cache")
    
    elif args.command == 'merge':
        if not args.secondary or not args.output:
            print("Error: --secondary and --output required for merge")
            exit(1)
        merge_tag_caches(args.cache, args.secondary, args.output)