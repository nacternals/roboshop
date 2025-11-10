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



echo "========= 2) Lists (plain strings & arguments) ========="
# A "list" can just be a string with words separated by spaces.
# NOTE: Word splitting happens on whitespace; be careful with items containing spaces.
list="dev test stage prod"
echo "As words from a string:"
for env in $list; do
	echo "  env: $env"
done

# Safer list when elements may have spaces -> use an array or readarray/mapfile
echo "Safer list using readarray (preserves spaces/newlines):"
mapfile -t items < <(printf '%s\n' "alpha one" "beta two" "gamma three")
for item in "${items[@]}"; do
	echo "  item: $item"
done
echo



echo "======= 3) Associative Array (Map: key -> value) ======="
# Bash 4+ required
declare -A ports
ports=(
	[nginx]=80
	[ssh]=22
	[vault]=8200
)

# Access by key
echo "nginx runs on: ${ports[nginx]}"

# Add/update
ports[redis]=6379

# Iterate keys
echo "All services and ports:"
for svc in "${!ports[@]}"; do
	#printf "  %s -> %s\n" "$svc" "${ports[$svc]}"
	echo "$svc" "${ports[$svc]}"
done

echo "Done."
