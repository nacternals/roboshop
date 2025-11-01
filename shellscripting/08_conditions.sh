#!/usr/bin/env bash

#This script demonstrates shell conditions like if, if-else, and if-elif-else.
echo -e "\nThis script demonstrates shell conditions like if, if-else, and if-elif-else.\n"

englishMarks=$1

#Only if condition
echo -e "\nOnly if condition"
if (($englishMarks >= 35)); then
	echo "PASS"
fi

#if-else condition
echo -e "\nif-else condition"
if (($englishMarks >= 35)); then
	echo "Pass"
else
	echo "Fail"
fi

#if-elif-else condition
echo -e "\nif-elif-else condition"
if ((englishMarks < 35)); then
	echo "Fail"
elif ((englishMarks >= 35 && englishMarks < 60)); then
	echo "Grade C"
elif ((englishMarks >= 60 && englishMarks < 90)); then
	echo "Grade B"
else
	echo "Grade A"
fi
