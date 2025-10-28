#Shebang
#!/usr/bin/env bash

blanklines() {
  local n=${1:-1}

  # Validate: non-negative integer
  if [[ ! $n =~ ^[0-9]+$ ]]; then
    printf 'Error: please provide a non-negative integer.\n' >&2
    return 1
  fi

  (( n == 0 )) && return 0

  # Fast path if `seq` exists; otherwise portable loop
  if command -v seq >/dev/null 2>&1; then
    printf '\n%.0s' $(seq 1 "$n")
  else
    for ((i=0; i<n; i++)); do
      printf '\n'
    done
  fi
}


#Hello World script
echo "Hello Neo; Matrix is waiting for you...."
blanklines 2

#Passing Command-line Arguments (pass more 3 command-line arguments)
echo "File Name: " $0
echo "First command-line argument: " $1
echo "Second command-line argument: " $2
echo "Third command-line argument: " $3
echo "All command-line arguments: " $@
echo "Total number of command-line arguments: " $#
blanklines 2

#variables
projectName="OptimusPrime"
today=$(date)
user=$(whoami)
userHomeDirectory=$HOME
userCurrentShell=$SHELL
userPath=$PATH

printf "Hi $user...Welcome to $projectName @$today."
blanklines
printf "Your current shell is $userCurrentShell "
blanklines
printf "Your home directory is $userHomeDirectory"
blanklines
#printf "Your path is $userPath .... "
blanklines 2

#Operators
#1. Assignment Operator:
name="Srinivas"              # string assignment
a=15                      # integer assignment
b=4
echo "Assignment Operators:"
echo "Hello, $name!"
echo "Starting with a=$a and b=$b"
blanklines 2

#2. Arithmatic Operators:
echo "Arithmetic Operators: "
sum=$((a + b))
diff=$((a - b))
prod=$((a * b))
quot=$((a / b))     # integer division
mod=$((a % b))

echo "  $a + $b = $sum"
echo "  $a - $b = $diff"
echo "  $a * $b = $prod"
echo "  $a / $b = $quot"
echo "  $a % $b = $mod"
blanklines 2


#3. Relational Operators
echo "Relational Operators:"
if [[ $a -eq $b ]]; then
  echo "  a is equal to b (-eq)"
fi

if [[ $a -ne $b ]]; then
  echo "  a is not equal to b (-ne)"
fi

if [[ $a -lt $b ]]; then
  echo "  a is less than b (-lt)"
fi

if [[ $a -gt $b ]]; then
  echo "  a is greater than b (-gt)"
fi

if [[ $a -le $b ]]; then
  echo "  a is less than or equal to b (-le)"
fi

if [[ $a -ge $b ]]; then
  echo "  a is greater than or equal to b (-ge)"
fi
blanklines 2

#4. String Comparison Operators:
city="Hyderabad"
echo "String Comparison Operators:"
if [[ $city = "Hyderabad" ]]; then
  echo "  city equals 'Hyderabad' (=)"
fi

if [[ $city != "Mumbai" ]]; then
  echo "  city is not 'Mumbai' (!=)"
fi
blanklines 2

#5. Conditions: if / if-else / if-elif-else ---
marks=82
echo "Conditions on marks=$marks:"
# if
if (( marks >= 90 )); then
  echo "  if: Outstanding"
fi

# if-else
if (( marks >= 90 )); then
  echo "  if-else: Grade A"
else
  echo "  if-else: Not A"
fi

# if-elif-else
if   (( marks >= 90 )); then
  echo "  if-elif-else: Grade A"
elif (( marks >= 75 )); then
  echo "  if-elif-else: Grade B"
else
  echo "  if-elif-else: Grade C"
fi
blanklines 2

# --- 5) User input with read ---
echo "User Input Demo:"
read -p "  Enter your first number: " x
read -p "  Enter your second number: " y
read -p "  Enter your favorite color: " color

# Basic validation and arithmetic on input
if ! [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]]; then
  echo "  Please enter valid integers for numbers."
  exit 1
fi

echo "  You entered x=$x and y=$y, color=$color"

# Show arithmetic again using user input
echo "  x + y = $((x + y))"
echo "  x - y = $((x - y))"
echo "  x * y = $((x * y))"
if [[ $y -ne 0 ]]; then
  echo "  x / y = $((x / y))"
  echo "  x % y = $((x % y))"
else
  echo "  Division/modulo skipped (y is 0)."
fi

# Relational check with user input
if [[ $x -gt $y ]]; then
  echo "  x is greater than y (-gt)"
elif [[ $x -lt $y ]]; then
  echo "  x is less than y (-lt)"
else
  echo "  x equals y (-eq)"
fi

# String check with user input
if [[ $color = "blue" ]]; then
  echo "  Nice, blue is cool!"
elif [[ $color != "" ]]; then
  echo "  $color is a nice color."
else
  echo "  You didn't enter a color."
fi