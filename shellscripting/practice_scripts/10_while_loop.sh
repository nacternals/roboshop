#!/usr/bin/env bash

#===============1. Read line by line from a file:=============
echo "Read line by line from a file:"

while IFS= read -r line; do
	echo "$line"
done </c/Users/srini/app/roboshop/shellscripting/practice_scripts/90_install_packages_function.sh

#===================2. Read line by line from a command's output:==============
echo -e "\nRead line by line from a command's output:"

while IFS= read -r line; do
	echo "$line"
done < <(ls -alt /c/Users/srini/app/roboshop/shellscripting/practice_scripts/)

#================3. Read line by line between EOF and EOF:===============
echo -e "\nRead line by line between EOF and EOF:"

while IFS= read -r line; do
	echo "$line"
done <<EOF
a
bc
def
ghij
klmno
pqrstu
vwxyz
EOF

#================4. Read line by line between cmd and cmd:================
echo -e "\nRead line by line between cmd and cmd:"

while IFS= read -r line; do
	echo "$line"
done <<cmd
echo "example echo1...."
print "example print....."
cmd

#===============5. Read line by line between straight line:===========
echo -e "\nRead line by line between straight line:"

while IFS= read -r line; do
	echo "$line"
done <<<"samepletextsampletextsampletext"
