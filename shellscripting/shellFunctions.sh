#!/usr/bin/env bash
# loops_and_functions — demos of for/while and functions in Bash

echo "Script for the below topics: "
echo "Simple for-loop (list, range, i++)"
echo "For-loop (read start, end, increment from user's input)"
echo "Simple while-loop ((read start, end, increment from user's input))"
echo "basic function"
echo "function with parameters"
echo "function with user's input"




set -euo pipefail

# ---------- helpers ----------
is_int() {
  # returns 0 if all args are integers; 1 otherwise
  local re='^-?[0-9]+$'
  for v in "$@"; do
    [[ $v =~ $re ]] || return 1
  done
  return 0
}

divider(){
     printf "\n---- %s ----\n" "$1"; 
}

# ---------- 1) Simple for-loops ----------
divider "Simple for-loop"

# 1a) for-loop over a LIST
for color in red green blue; do
  echo "List item: $color"
done

# 1b) for-loop over a RANGE (brace expansion)
for n in {1..5}; do
  echo "Range (brace): $n"
done

# 1c) C-style for-loop (i++)
for ((i=1; i<=5; i++)); do
  echo "C-style i++: $i"
done

# ---------- 2) For-loop with user input (start, end, increment) ----------
divider "For-loop from user input"
read -rp "Enter START: " start
read -rp "Enter END: " end
read -rp "Enter INCREMENT: " step

if ! is_int "$start" "$end" "$step" || [[ $step -eq 0 ]]; then
  echo "Please enter valid integers (step cannot be 0)."
  exit 1
fi

# choose comparison based on step sign
if (( step > 0 )); then
  for ((i=start; i<=end; i+=step)); do
    echo "for-loop i=$i"
  done
else
  for ((i=start; i>=end; i+=step)); do
    echo "for-loop i=$i"
  done
fi

# ---------- 3) While-loop with user input (start, end, increment) ----------
divider "While-loop from user input"
read -rp "Enter START: " w_start
read -rp "Enter END: " w_end
read -rp "Enter INCREMENT: " w_step

if ! is_int "$w_start" "$w_end" "$w_step" || [[ $w_step -eq 0 ]]; then
  echo "Please enter valid integers (step cannot be 0)."
  exit 1
fi

i=$w_start
if (( w_step > 0 )); then
  while (( i <= w_end )); do
    echo "while-loop i=$i"
    (( i += w_step ))
  done
else
  while (( i >= w_end )); do
    echo "while-loop i=$i"
    (( i += w_step ))
  done
fi

# ---------- 4) Basic function ----------
divider "Basic function"
hello() {
  echo "Hello from a basic function!"
}
hello

# ---------- 5) Function with parameters ----------
divider "Function with parameters"
add() {
  # usage: add NUM1 NUM2
  if ! is_int "${1:-}" "${2:-}"; then
    echo "add: please pass two integers" >&2
    return 2
  fi
  local a=$1 b=$2
  echo "$a + $b = $((a + b))"
}
add 7 13

# ---------- 6) Function that asks user for input ----------
divider "Function with user input"
multiply_from_user() {
  read -rp "Enter X: " x
  read -rp "Enter Y: " y
  if ! is_int "$x" "$y"; then
    echo "Please enter integers."
    return 3
  fi
  echo "$x * $y = $((x * y))"
}
multiply_from_user

divider "Done"
