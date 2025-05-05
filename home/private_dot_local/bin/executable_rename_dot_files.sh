#!/bin/bash

# Check if we are inside a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "Not inside a git repository."
	exit 1
fi

for file in .[^.]*; do
	if [ -f "$file" ]; then
		new_name="dot_${file:1}"
		git mv "$file" "$new_name"
	fi
done

echo "Renaming completed."
