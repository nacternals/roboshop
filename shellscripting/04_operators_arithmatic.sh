#!/usr/bin/env bash

#this script demonstrates how arithmatic operators behave in a shell script

firstNumber=$1
secondNumber=$2

echo -e "\nThis script demonstrates how arithmatic operators behave in a shell script\n"
echo -e " ${firstNumber} + ${secondNumber} = $((firstNumber+secondNumber))"
echo -e " ${firstNumber} - ${secondNumber} = $((firstNumber-secondNumber))"
echo -e " ${firstNumber} * ${secondNumber} = $((firstNumber*secondNumber))"
echo -e " ${firstNumber} / ${secondNumber} = $((firstNumber/secondNumber))"
echo -e " ${firstNumber} % ${secondNumber} = $((firstNumber%secondNumber))"