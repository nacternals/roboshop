#!/usr/bin/env bash

#This script demonstrates how string comparison operators behave in a shell script.
echo -e "\nThis script demonstrates how string comparison operators behave in a shell script.\n"

firstPerson=$1
secondPerson=$2

if [[ "$firstPerson" == "$secondPerson" ]]; then
	echo "$firstPerson is same as $secondPerson"
else
	echo "$firstPerson is not same as $secondPerson"
fi
