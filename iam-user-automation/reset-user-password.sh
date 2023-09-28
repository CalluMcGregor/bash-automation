#!/usr/bin/env bash

# Reset a users password using AWS CLI

USERNAME=$1 #iam user name
PASSWORD=$2 #the password users will use to sign in with before resetting
REGION="eu-west-2"
ACTION="none"

ylw='\033[0;33m' #command starting colour
grn='\033[0;32m' #command completed colour
clr='\033[0m' #clear/remove colour

# Verify user profile exists
AWS_PROFILE=pdp-dev-admin aws iam get-login-profile \
    --user-name ${USERNAME}                         \
    --region ${REGION}                              \
    > /dev/null 2>&1

if [ $? -gt 0 ]; then #checks exit code of above command, if exit code > 0, create-login-profile
    echo -e "${ylw}\nUser's first login - creating a new user profile.${clr}"
    ACTION="create-login-profile"
else #user already has a login profile, update-login-profile
    echo -e "${ylw}\nNot user's first login - updating existing user profile.${clr}"
    ACTION="update-login-profile"
fi

if [ -z "${PASSWORD}" ]; then #if new temporary password wasn't given, prompt for one
  echo -e "\nEnter a temporary password for the user: "
  echo -e "(Passwords must have uppercase, lowercase, numbers, and special characters)"
  read PASSWORD
fi

AWS_PROFILE=pdp-dev-admin aws iam ${ACTION} \
    --user-name ${USERNAME}                 \
    --password ${PASSWORD}                  \
    --password-reset-required               \
    --region ${REGION}                      \
    && echo -e "${grn}\nUser's password has been set/reset. Provide the user with their new temporary password.${clr}"


