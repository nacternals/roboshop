#!/usr/bin/env bash

#this script demonstrates how variables behave in a shell script
todayDate=$(date +"%F %T")
name=$1
age=$2

echo -e "Today's date is ${todayDate}\n"
echo -e "DevOps engineer name is ${name} and age is ${age}\n"
