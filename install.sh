#!/bin/bash
# -------
# Script for install of Alfresco
#
# Copyright 2013-2017 Loftux AB, Peter Löfgren
# Copyright 2020 Salvatore De Paolis <iwkse@claws-mail.org> Iurit
# Distributed under the Creative Commons Attribution-ShareAlike 3.0 Unported License (CC BY-SA 3.0)
# -------

source src/vars.sh
source src/urls.sh
source src/packages.sh

echo -n "Path for Alfresco Debian installer temporary files (~/alfinst): "
read;
test -z $REPLY || TMP_INSTALL=$REPLY
test -d $TMP_INSTALL && (rm -rf $TMP_INSTALL && mkdir $TMP_INSTALL) || mkdir $TMP_INSTALL

pushd $TMP_INSTALL

  echog "Alfresco Debian installer by Iurit."
  echog "Please read the documentation at"
  echog "https://github.com/iwkse/alfresco-debian-install."

  if [ $# -eq 0 ]; then
    apt_update
    check_tools
    check_remote_urls
    locale_support
    security_limits
    tomcat_install
    nginx_install
    java_install
    libreoffice_install
    imagemagick_install
    basicsupport_install
    keystore_install
    wars_install
    apply_wars
    solr_install
    bart_install
  else
    if [ "$1" = 'tomcat' ]; then
      tomcat_install
    fi
    if [ "$1" = 'nginx' ]; then
echo "feeto"
      nginx_install
    fi
    if [ "$1" = 'java' ]; then
      java_install
    fi
  fi
popd

rm -rf $TMP_INSTALL

echog "- - - - - - - - - - - - - - - - -"
echo "Scripted install complete"
echo
echor "Manual tasks remaining:"
echo
echo "1. Add database. Install scripts available in $ALF_HOME/scripts"
echor "   It is however recommended that you use a separate database server."
echo
echo "2. Verify Tomcat memory and locale settings in the file"
echo "   $ALF_HOME/alfresco-service.sh."

echo "   Alfresco runs best with lots of memory. Add some more to \"lots\" and you will be fine!"
echo "   Match the locale LC_ALL (or remove) setting to the one used in this script."
echo "   Locale setting is needed for LibreOffice date handling support."
echo
echo "3. Update database and other settings in alfresco-global.properties"
echo "   You will find this file in $CATALINA_HOME/shared/classes"
echor "   Really, do this. There are some settings there that you need to verify."
echo
echo "4. Update properties for BART (if installed) in $ALF_HOME/scripts/bart/alfresco-bart.properties"
echo "   DBNAME,DBUSER,DBPASS,DBHOST,REC_MYDBNAME,REC_MYUSER,REC_MYPASS,REC_MYHOST,DBTYPE "
echo
echo "5. Update cpu settings in $ALF_HOME/scripts/limitconvert.sh if you have more than 2 cores."
echo
echo "6. Start nginx if you have installed it: sudo service nginx start"
echo
echo "7. Start Alfresco/tomcat:"
echo "   $ALF_HOME/alfresco-service.sh start"
echo
echo
echo "${warn}${bldblu} - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ${warn}"
echog "Thanks for using Alfresco Debian installer by Iurit."
echog "This is a port of the Alfresco Ubuntu installer by Loftux AB"
echog "Please visit https://loftux.com for more Alfresco Services and add-ons."
echog "You are welcome to contact us at info@loftux.se"
echo "${warn}${bldblu} - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ${warn}"
echo
exec bash
