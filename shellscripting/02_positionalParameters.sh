#!/usr/bin/env bash

#this script explain how positional parameters behave
echo -e "Script Name: $0\n"
echo -e "First Command-line Argument: $1\n"
echo -e "Second Command-line Argument: $2\n"
echo -e "Third Command-line Argument: $3\n"
echo -e "All Command-line Arguments: $@\n"
echo -e "Total Number of Command-line Arguments: $#\n"
