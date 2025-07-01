#!/usr/bin/env -S uv run --script
"""Clean expired cache entries or show cache statistics."""
# /// script
# dependencies = []
# ///

import argparse
import json
import time
from pathlib import Path


def show_cache_stats(cache_file: str = ".repology_cache.json", ttl_days: int = 7):
    """Show cache statistics."""
    ttl_seconds = ttl_days * 24 * 60 * 60

    if not Path(cache_file).exists():
        print("No cache file found")
        return

    # Load cache
    with open(cache_file) as f:
        cache = json.load(f)

    current_time = time.time()
    total_entries = len(cache)
    fresh_count = 0
    expired_count = 0
    no_timestamp = 0

    for package, entry in cache.items():
        if isinstance(entry, dict) and "_timestamp" in entry:
            if (current_time - entry["_timestamp"]) <= ttl_seconds:
                fresh_count += 1
            else:
                expired_count += 1
        else:
            no_timestamp += 1

    print(f"📊 Total entries: {total_entries}")
    print(f"✅ Fresh entries: {fresh_count}")
    print(f"⏰ Expired entries: {expired_count}")
    print(f"❓ No timestamp: {no_timestamp}")

    # Calculate file size
    file_size = Path(cache_file).stat().st_size
    if file_size > 1024 * 1024:
        size_str = f"{file_size / (1024 * 1024):.1f} MB"
    elif file_size > 1024:
        size_str = f"{file_size / 1024:.1f} KB"
    else:
        size_str = f"{file_size} bytes"

    print(f"💾 Cache size: {size_str}")

    # Age-based refresh information
    if total_entries > 0:
        daily_refresh_count = max(1, total_entries // 7)
        print(f"🗂️ Daily refresh: ~{daily_refresh_count} oldest packages")
        print("📅 Refresh strategy: Age-based (oldest entries first)")

        # Show age distribution
        if fresh_count > 0 and expired_count > 0:
            print(f"🔄 Cache health: {(fresh_count/total_entries)*100:.1f}% fresh entries")


def clean_expired_cache(cache_file: str = ".repology_cache.json", ttl_days: int = 7, remove_empty: bool = False):
    """Clean expired entries from cache file."""
    backup_file = cache_file + ".backup"
    ttl_seconds = ttl_days * 24 * 60 * 60

    if not Path(cache_file).exists():
        print("No cache file found")
        return

    # Create backup
    import shutil

    shutil.copy2(cache_file, backup_file)

    # Load cache
    with open(cache_file) as f:
        cache = json.load(f)

    current_time = time.time()
    fresh_cache = {}
    error_entries_removed = 0
    empty_entries_removed = 0

    # Keep only fresh entries and remove error results
    for package, entry in cache.items():
        if isinstance(entry, dict) and "_timestamp" in entry:
            # Check if it's an error result (null data or all platforms false)
            is_error_result = False
            is_empty_entry = False
            
            if "data" in entry and entry["data"] is None:
                is_error_result = True
            elif "platforms" in entry:
                # Check if all platforms are false (indicates empty entry)
                platforms = entry.get("platforms", {})
                if isinstance(platforms, dict) and all(not v for v in platforms.values()):
                    if remove_empty:
                        is_empty_entry = True
                        empty_entries_removed += 1
                    else:
                        is_error_result = True

            if is_error_result:
                error_entries_removed += 1
                continue  # Skip error results
                
            if is_empty_entry:
                continue  # Skip empty entries when remove_empty=True

            # Keep fresh, non-error entries
            if (current_time - entry["_timestamp"]) <= ttl_seconds:
                fresh_cache[package] = entry

    # Write cleaned cache
    with open(cache_file, "w") as f:
        json.dump(fresh_cache, f, indent=2)

    # Remove backup
    Path(backup_file).unlink()

    expired_count = len(cache) - len(fresh_cache) - error_entries_removed - empty_entries_removed
    print(f"Kept {len(fresh_cache)} fresh entries out of {len(cache)} total")
    print(f"Removed {expired_count} expired entries and {error_entries_removed} error entries")
    if remove_empty:
        print(f"Removed {empty_entries_removed} empty entries (will be refreshed on next cache run)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clean expired cache entries or show stats")
    parser.add_argument(
        "cache_file", nargs="?", default=".repology_cache.json", help="Cache file path"
    )
    parser.add_argument(
        "--stats-only", action="store_true", help="Only show statistics, do not clean"
    )
    parser.add_argument("--ttl-days", type=int, default=7, help="TTL in days (default: 7)")
    parser.add_argument(
        "--remove-empty", action="store_true", 
        help="Remove empty entries (all platforms false) to force refresh"
    )

    args = parser.parse_args()

    if args.stats_only:
        show_cache_stats(args.cache_file, args.ttl_days)
    else:
        clean_expired_cache(args.cache_file, args.ttl_days, remove_empty=args.remove_empty)
