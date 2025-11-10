#!/usr/bin/env bash

#This script demonstrates how to install packages with the help of:
#if
#if-else
#if-elif-else

echo -e "This script demonstrates how to install packages (git vim wget net-tools )with the help of:
#if
#if-else
#if-elif-else"

#Installing git
echo -e "\nInstalling git"
echo "Checking whether git is already installed or not"

# 1. Is current user is root. If not, change to root suer
# If yes, proceed to further
# 2. Is git already installed. If not, install git
# If yes, show to user that git is already installed and exit.

userID=$(id -u)
if (($userID != 0)); then
	echo "Insufficient access; please change to root access"
	exit 1
else
	echo "Sufficient root access is present; proceeding further to install the requested packages."
	yum -q list installed git &>/dev/null
	if (($? != 0)); then
		yum install git -y
		if (($? != 0)); then
			echo "Git has been installed successfully."
		fi

	else
		echo "Git already installed."
	fi
fi

#Installing nginx
echo -e "\nInstalling nginx"
echo "Checking whether nginx is already installed or not"

userID=$(id -u)
if (($userID != 0)); then
	echo "Insufficient access; please change to root access"
	exit 1
else
	echo "Sufficient root access is present; proceeding further to install the requested packages."
	yum -q list installed nginx &>/dev/null
	if (($? != 0)); then
		echo "Nginx is not yet installed; now, installing it...."
		if dnf -y install nginx &> /dev/null; then
			echo "Nginx has been installed successfully."
		else
			echo "Nginx installation failed."
		fi
		# yum install nginx -y
		# if (($? == 0)); then
		# 	echo "Nginx has been installed successfully."
		# fi

	else
		echo "Nginx has already been installed."
	fi
fi
