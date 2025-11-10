#!/usr/bin/env bash

set -euo pipefail

# Demo of arrays, lists, and maps in Bash
echo "Demo of arrays, lists, and maps in Bash...."



echo "========= 1) Indexed Array (array[]) ========="
# Create an indexed array
fruits=(apple banana "dragon fruit" cherry mango)

# Access by it's index
echo "First fruit: ${fruits[0]}"

# Count & print all
echo "Total fruits: ${#fruits[@]}"
echo "All fruits: ${fruits[*]}"

# Append and iterate with index
fruits+=("elderberry")
echo "After append:"
for i in "${!fruits[@]}"; do
	printf "  [%d] %s\n" "$i" "${fruits[$i]}"
done

# Slice (from index 1, take 2)
echo "Slice (index 1..2): ${fruits[@]:1:2}"
echo


