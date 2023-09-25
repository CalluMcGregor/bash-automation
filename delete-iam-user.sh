#!/usr/bin/env bash

# Terraform cannot delete IAM users when they have any of the following dependencies in AWS:
# Password (DeleteLoginProfile)
# Access Keys (DeleteAccessKey)
# SSH Keys (DeleteSSHPublicKey)
# Git Credentials (DeleteServiceSpecificCredential)
# MFA Device (DeactivateMFADevice)
# Managed Policies (DetachUserPolicy)
# Group memberships (RemoveUserFromGroup)
# This script removes all of these dependencies and deletes the IAM user from the console
# It then optionally deletes the user.tf file,  and removes the user's name from the group-membership.tf file

# NOTE: SCRIPT REQUIRES GNU-SED -- brew install gnu-sed

USERNAME=$1 #IAM user name
AUTO_DELETE=$2 #yes/y or no/n = automatically remove user file and from group-membership.tf
REGION="eu-west-2"
USER_ACCOUNT=$3

ylw='\033[0;33m' #command starting colour
grn='\033[0;32m' #command completed colour
cyn='\033[0;36m' #username/object colour
red='\033[0;31m' #warning/error colour
prpl='\033[0;35m' #user input prompt colour
clr='\033[0m' #clear/remove colour

echo -e "${grn}--------------------------------------------${clr}"

################ DETACH USER POLICIES ################
echo -e "\n${ylw}Getting IAM user policies of user: ${cyn}${USERNAME}${clr}"
POLICY_ARN_LIST="$(aws iam list-attached-user-policies    \
  --user-name ${USERNAME}                                 \
  --region ${REGION}                                      \
  --query "AttachedPolicies[].PolicyArn"                  \
  --output text
  )"

if [ ${#POLICY_ARN_LIST} -gt 0 ]; then
  for POLICY_ARN in ${POLICY_ARN_LIST}; do
    POLICY_ARN=$(echo "$POLICY_ARN" | tr -d '"')
    AWS_PROFILE=pdp-dev-admin aws iam detach-user-policy   \
      --user-name ${USERNAME}                              \
      --policy-arn ${POLICY_ARN}                           \
      --region ${REGION}
    echo -e "${grn}Detached policy: ${cyn}${POLICY_ARN}${grn}${clr}"
  done
else
  echo -e "${grn}Zero policies found attached to user: ${cyn}${USERNAME}${clr}"
fi

################ REMOVE LOGIN PROFILE (PASSWORD) ################
echo -e "\n${ylw}Removing login profile of user: ${cyn}${USERNAME}${clr}"
AWS_PROFILE=pdp-dev-admin aws iam delete-login-profile \
      --user-name ${USERNAME}                          \
      --region ${REGION}                               \
      || (echo -e "${red}^The user has no login profile, so it could not be removed${clr}"; exit 1)

echo -e "${grn}Confirmed that user has no login profile${clr}"

################ REMOVE USER MFA ################
echo -e "\n${ylw}Removing MFA for user: ${cyn}${USERNAME}${clr}"
MFA_LIST=$( AWS_PROFILE=pdp-dev-admin aws iam list-mfa-devices    \
    --user-name ${USERNAME}                                       \
    --query "MFADevices[].SerialNumber"                           \
    --region ${REGION}                                            \
    --output text )

for MFA in ${MFA_LIST}; do
    AWS_PROFILE=pdp-dev-admin aws iam deactivate-mfa-device    \
        --user-name ${USERNAME}                                \
        --serial-number  "${MFA}"                              \
        --region ${REGION}
    echo -e "${grn}Removed MFA device: ${cyn}${MFA}${clr}\n"
done

################ REMOVE USER ACCESS KEYS ################
echo -e "\n${ylw}Removing Access Keys for user: ${cyn}${USERNAME}${clr}"
KEY_LIST=$( AWS_PROFILE=pdp-dev-admin aws iam list-access-keys \
    --user-name ${USERNAME}                                    \
    --query "AccessKeyMetadata[].AccessKeyId"                  \
    --region ${REGION}                                         \
    --output text )

for KEY_ID in ${KEY_LIST}; do
    AWS_PROFILE=pdp-dev-admin aws iam delete-access-key \
        --user-name ${USERNAME}                         \
        --access-key-id ${KEY_ID}                       \
        --region ${REGION}
    echo -e "${grn}Removed access key: ${cyn}${KEY_ID}${clr}\n"
done

################ REMOVE USER SSH KEYS ################
echo -e "\n${ylw}Removing SSH Keys for user: ${cyn}${USERNAME}${clr}"
SSH_LIST=$( AWS_PROFILE=pdp-dev-admin aws iam list-ssh-public-keys \
    --user-name ${USERNAME}                                        \
    --query "SSHPublicKeys[].SSHPublicKeyId"                       \
    --region ${REGION}                                             \
    --output text
     )

for KEY in ${SSH_LIST}; do
    AWS_PROFILE=pdp-dev-admin aws iam delete-ssh-public-key \
        --user-name ${USERNAME}                             \
        --ssh-public-key-id ${KEY}                          \
        --region ${REGION}
    echo -e "${grn}Removed SSH key: ${cyn}${KEY}${clr}\n"
done

################ REMOVE USER SERVICE SPECIFIC KEYS (Git/CodeCommit) ################
echo -e "\n${ylw}Removing Service Specific Credentials for user: ${cyn}${USERNAME}${clr}"
CREDS_LIST=$( AWS_PROFILE=pdp-dev-admin aws iam list-service-specific-credentials \
            --user-name ${USERNAME}                                               \
            --region ${REGION}                                                    \
            --query "ServiceSpecificCredentials[].ServiceSpecificCredentialId"    \
            --output text )

for CRED in ${CREDS_LIST}; do
    AWS_PROFILE=pdp-dev-admin aws iam delete-service-specific-credential \
        --user-name ${USERNAME}                                          \
        --service-specific-credential-id ${CRED}                         \
        --region ${REGION}
    echo -e "${grn}Removed service specific credential: ${cyn}${CRED}${clr}"
done

################ REMOVE USER FROM USER GROUPS ################
echo -e "\n${ylw}Removing group memberships for user: ${cyn}${USERNAME}${clr}"
GROUPS_LIST=$(AWS_PROFILE=pdp-dev-admin aws iam list-groups-for-user \
            --user-name ${USERNAME}                                  \
            --region ${REGION}                                       \
            --query "Groups[].GroupName"                             \
            --output text )

for GROUP in ${GROUPS_LIST}; do
  AWS_PROFILE=pdp-dev-admin aws iam remove-user-from-group \
    --user-name ${USERNAME}                                \
    --group-name ${GROUP}                                  \
    --region ${REGION}
  echo -e "${grn}Removed user from group: ${cyn}${GROUP}${clr}"
done

############### REMOVE USER IAM IN CONSOLE ################
echo -e "\n${ylw}Deleting IAM User: ${cyn}${USERNAME}${clr}"
AWS_PROFILE=pdp-dev-admin aws iam delete-user \
  --user-name ${USERNAME}                     \
  --region ${REGION}
echo -e "${grn}Deleted IAM user from AWS${clr}\n"

############### (OPTIONAL) DELETE USER IAM FILE AND GROUP MEMBERSHIP ################
delete_user_file() #function to delete user file
{
  echo -e "${ylw}Deleting Terraform file of user: ${cyn}${USERNAME}${clr}"
  if [ -f "iam-users/user.${USERNAME}.tf" ]; then
    rm iam-users/user.${USERNAME}.tf
    echo -e "${grn}Successfully deleted user.tf Terraform file${clr}\n"
  else
    echo -e "${red}Could not find a file to remove called user.${USERNAME}.tf in iam-users/${clr}"
  fi
}
remove_group_membership() #function to remove user from groups in group-membership.tf
{
  LINES="$(gsed -n '/"test.test"/=' iam-users/group-membership.tf)"
  if [ -z "$LINES" ]; then
    echo -e "${grn}Group-membership.tf contains no instances of the user's name${clr}"
  else
    echo -e "${ylw}Removing name from group-membership.tf file for user: ${cyn}${USERNAME}${clr}"
    echo -e "${grn}User's name appears on line(s):\n ${cyn}${LINES}"
    gsed -i "/${USERNAME}/d" iam-users/group-membership.tf
    echo -e "${grn}Successfully removed all name instances from group-membership.tf${clr}"
  fi
}

if [ -z "$AUTO_DELETE" ]; then #if the user did not provide an AUTO_DELETE value, prompt them for one
  echo -e "\n${prpl}Remove user.tf file and name from group-membership.tf? ${grn}(y/n):${clr}"
  read AUTO_DELETE
  if [ $AUTO_DELETE = 'y' ] || [ $AUTO_DELETE = 'yes' ]; then
    delete_user_file
    remove_group_membership
  else
    echo -e "${red}You'll need to manually remove the user's file and group-membership.tf placements yourself!${clr}"
  fi
else #the user did provide an AUTO_DELETE value, act accordingly
  if [ $AUTO_DELETE = 'y' ] || [ $AUTO_DELETE = 'yes' ]; then
    delete_user_file
    remove_group_membership
  else
    echo -e "${red}You'll need to manually remove the user's file and group-membership.tf placements yourself!${clr}"
  fi
fi

echo -e "\n${grn}--------------------------------------------${clr}"
