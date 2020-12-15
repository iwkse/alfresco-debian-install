#!/bin/bash

ALF_HOME=$HOME/alfresco
INST_SOURCE=$(pwd)
ALF_DATA_HOME=$ALF_HOME/alf_data
CATALINA_HOME=$ALF_HOME/tomcat
ALF_USER=$USER
ALF_GROUP=$ALF_USER
APTVERBOSITY="-qq -y"
TMP_INSTALL=$HOME/alfinst
DEFAULTYESNO="y"
NGINX_CACHE=$ALF_HOME/nginx_cache/alfresco
TEMPLATES=$INST_SOURCE/templates
USE_MARIADB=
USE_POSTGRESQL=

#Change this to prefered locale to make sure it exists. This has impact on LibreOffice transformations
LOCALESUPPORT=en_US.UTF-8

BART_PROPERTIES=alfresco-bart.properties
BART_EXECUTE=alfresco-bart.sh

# Color variables
txtund=$(tput sgr 0 1)          # Underline
txtbld=$(tput bold)             # Bold
bldred=${txtbld}$(tput setaf 1) #  red
bldgre=${txtbld}$(tput setaf 2) #  red
bldblu=${txtbld}$(tput setaf 4) #  blue
bldwht=${txtbld}$(tput setaf 7) #  white
txtrst=$(tput sgr0)             # Reset
info=${bldwht}*${txtrst}        # Feedback
pass=${bldblu}*${txtrst}
warn=${bldred}*${txtrst}
ques=${bldblu}?${txtrst}

function echob 
{
  echo "${bldblu}$1${txtrst}"
}
function echor 
{
  echo "${bldred}$1${txtrst}"
}
function echog 
{
  echo "${bldgre}$1${txtrst}"
}
function printfb 
{
  printf "${bldblu}$1${txtrst}"
}
function printfr 
{
  printf "${bldred}$1${txtrst}"
}
function printfg
{
  printf "${bldgre}$1${txtrst}"
}
