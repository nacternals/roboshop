#!/bin/usr/env bash

#This script demonstrates how to read input from user.
echo -e "\nThis script demonstrates how to read values from a user."
set -euo pipefail

#Reading single value from user
read -p "Please Enter Your Age: " age
if (($age >= 18)); then
	echo "You are a major"
else
	echo "You are a minor"
fi

#Reading multiple values from user
read -sp "Please Enter Your Password: " password
echo  ""
read -p "Please Confirm Your Password: " confirmPassword

if [[ "$password" == "$confirmPassword" ]]; then
	echo "Passwords have been matched and set successfully."
else
	echo "Passwords have not been matched"
fi
