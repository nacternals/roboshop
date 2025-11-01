#!/usr/bin/env bash

#This script demonstrates how relational operators behave in a shell script.
echo -e "\nThis script demonstrates how relational operators behave in a shell script.\n"

firstNumber=$1
secondNumber=$2

if ((firstNumber == secondNumber)); then
	echo "$firstNumber is equal to $secondNumber."
else
	echo "$firstNumber is not equal to $secondNumber. "
fi
