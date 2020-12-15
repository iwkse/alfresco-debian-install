#!/bin/bash

function apt_update
{
  printfb "Preparing for install. Updating the apt package index files..."
  sudo apt-get $APTVERBOSITY update
  echog "[OK]"
}

function check_tools
{
  if [ -x "$(command -v systemctl)" ]; then
    echo "You are installing for version 10 or later (using systemd for services)."
  else 
    echor "Systemctl not found! Can't continue"
    exit 1
  fi

  if [ ! -x "$(command -v curl)" ]; then
    printfb "Installing curl..."
    sudo apt-get $APTVERBOSITY install curl;
    echog "[OK]"
  fi

  if [ ! -x "$(command -v wget)" ]; then
    printfb "Installing wget..."
    sudo apt-get $APTVERBOSITY install wget;
    echog "[OK]"
  fi
}

function check_remote_urls
{
  URLERROR=0

  for REMOTE in $TOMCAT_DOWNLOAD $JDBCPOSTGRESURL/$JDBCPOSTGRES $JDBCMYSQLURL/$JDBCMYSQL \
          $LIBREOFFICE $ALFREPOWAR $ALFSHAREWAR $ALFSHARESERVICES $GOOGLEDOCSREPO \
          $GOOGLEDOCSSHARE $ASS_DOWNLOAD $AOS_VTI $AOS_SERVER_ROOT
  do
    wget --spider $REMOTE --no-check-certificate >& /dev/null
    if [ $? != 0 ]; then
      echor "In alfinstall.sh, please fix this URL: $REMOTE"
      URLERROR=1
    fi
  done

  if [ $URLERROR = 1 ]
  then
    echor "Please fix the above errors and rerun."
    exit
  fi
}

function locale_support
{
  echo "You need to set the locale to use when running tomcat Alfresco instance."
  echo "This has an effect on date formats for transformations and support for"
  echo "international characters."

  read -e -p "Enter the default locale to use: " -i "$LOCALESUPPORT" LOCALESUPPORT
  #install locale to support that locale date formats in open office transformations
  sudo sed -i "s/^# \($LOCALESUPPORT UTF-8\)/\1/" /etc/locale.gen
  sudo locale-gen 
  echog "Finished updating locale"
}

function security_limits
{
  echo "Debian default for number of allowed open files in the file system is too low"
  echo "for alfresco use and tomcat may because of this stop with the error"
  echo "\"too many open files\". You should update this value if you have not done so."
  echo "Read more at http://wiki.alfresco.com/wiki/Too_many_open_files"
  read -e -p "Add limits.conf${ques} [y/n] " -i "$DEFAULTYESNO" updatelimits
  if [ "$updatelimits" = "y" ]; then
    cat /etc/security/limits.conf | grep "alfresco" > /dev/null
    if [ $? -eq 1 ]; then
      echo "alfresco  soft  nofile  8192" | sudo tee -a /etc/security/limits.conf
      echo "alfresco  hard  nofile  65536" | sudo tee -a /etc/security/limits.conf
      echog "Updated /etc/security/limits.conf"
    fi
    cat /etc/pam.d/common-session | grep "pam_limits" > /dev/null
    if [ $? -eq 1 ]; then
      echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session
      echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session-noninteractive
      echog "Updated /etc/security/common-session*"
    fi
  else
    echo "Skipped updating limits.conf"
  fi
}

function tomcat_install
{
  echo "Tomcat is the application server that runs Alfresco."
  echo "You will also get the option to install jdbc lib for Postgresql or MySql/MariaDB."
  echo "Install the jdbc lib for the database you intend to use."
  read -e -p "Install Tomcat${ques} [y/n] " -i "$DEFAULTYESNO" installtomcat

  if [ "$installtomcat" = "y" ]; then
    echog "Installing Tomcat"
    echo "Downloading tomcat..."
    curl -# -L -O $TOMCAT_DOWNLOAD
    # Make sure install dir exists, including logs dir
    mkdir -p $ALF_HOME/logs
    echo "Extracting..."
    test -d $CATALINA_HOME || mkdir -p $CATALINA_HOME
    tar xf "$(find . -maxdepth 1 -type f -name "apache-tomcat*")" -C $CATALINA_HOME
    # Remove apps not needed
    rm -rf $CATALINA_HOME/webapps/*
    # Create Tomcat conf folder
    mkdir -p $CATALINA_HOME/conf/Catalina/localhost
    # Get Alfresco config
    echo "Downloading tomcat configuration files..."
    
    cp $TEMPLATES/tomcat/server.xml $CATALINA_HOME/conf/server.xml
    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $CATALINA_HOME/conf/server.xml 
    cp $TEMPLATES/tomcat/catalina.properties $CATALINA_HOME/conf/catalina.properties
    cp $TEMPLATES/tomcat/tomcat-users.xml $CATALINA_HOME/conf/tomcat-users.xml
    cp $TEMPLATES/tomcat/context.xml $CATALINA_HOME/conf/context.xml
    sudo cp $TEMPLATES/tomcat/alfresco.service /etc/systemd/system/alfresco.service
    sudo sed -i "s!@@INSTHOME@@!$ALF_HOME!g" /etc/systemd/system/alfresco.service 
    cp $INST_SOURCE/scripts/alfresco-service.sh $ALF_HOME/alfresco-service.sh
    chmod 755 $ALF_HOME/alfresco-service.sh
    sed -i "s/@@LOCALESUPPORT@@/$LOCALESUPPORT/g" $ALF_HOME/alfresco-service.sh 
    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $ALF_HOME/alfresco-service.sh 
    # Enable the service
    sudo systemctl enable alfresco.service
    sudo systemctl daemon-reload
    
    # Create /shared
    mkdir -p $CATALINA_HOME/shared/classes/alfresco/extension
    mkdir -p $CATALINA_HOME/shared/classes/alfresco/web-extension
    mkdir -p $CATALINA_HOME/shared/lib
    
    # Add endorsed dir
    mkdir -p $CATALINA_HOME/endorsed

    echo "You need to add the dns name, port and protocol for your server(s)."
    echo "It is important that this is is a resolvable server name."
    echo "This information will be added to default configuration files."
    read -e -p "Please enter the public host name for Share server (fully qualified domain name)${ques} [`hostname`] " -i "`hostname`" SHARE_HOSTNAME
    read -e -p "Please enter the protocol to use for public Share server (http or https)${ques} [http] " -i "http" SHARE_PROTOCOL
    SHARE_PORT=80
    if [ "${SHARE_PROTOCOL,,}" = "https" ]; then
      SHARE_PORT=443
    fi
    read -e -p "Please enter the host name for Alfresco Repository server (fully qualified domain name) as shown to users${ques} [$SHARE_HOSTNAME] " -i "$SHARE_HOSTNAME" REPO_HOSTNAME
    read -e -p "Please enter the host name for Alfresco Repository server that Share will use to talk to repository${ques} [localhost] " -i "localhost" SHARE_TO_REPO_HOSTNAME
    # Add default alfresco-global.propertis
    ALFRESCO_GLOBAL_PROPERTIES=$TMP_INSTALL/alfresco-global.properties
    cp $TEMPLATES/tomcat/alfresco-global.properties $ALFRESCO_GLOBAL_PROPERTIES
    sed -i "s/@@ALFRESCO_SHARE_SERVER@@/$SHARE_HOSTNAME/g" $ALFRESCO_GLOBAL_PROPERTIES
    sed -i "s/@@ALFRESCO_SHARE_SERVER_PORT@@/$SHARE_PORT/g" $ALFRESCO_GLOBAL_PROPERTIES
    sed -i "s/@@ALFRESCO_SHARE_SERVER_PROTOCOL@@/$SHARE_PROTOCOL/g" $ALFRESCO_GLOBAL_PROPERTIES
    sed -i "s/@@ALFRESCO_REPO_SERVER@@/$REPO_HOSTNAME/g" $ALFRESCO_GLOBAL_PROPERTIES
    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $ALFRESCO_GLOBAL_PROPERTIES 
    mv $ALFRESCO_GLOBAL_PROPERTIES $CATALINA_HOME/shared/classes/

    read -e -p "Install Share config file (recommended)${ques} [y/n] " -i "$DEFAULTYESNO" installshareconfig
    if [ "$installshareconfig" = "y" ]; then
      SHARE_CONFIG_CUSTOM=$TMP_INSTALL/share-config-custom.xml
      cp $TEMPLATES/tomcat/share-config-custom.xml $SHARE_CONFIG_CUSTOM
      sed -i "s/@@ALFRESCO_SHARE_SERVER@@/$SHARE_HOSTNAME/g" $SHARE_CONFIG_CUSTOM
      sed -i "s/@@SHARE_TO_REPO_SERVER@@/$SHARE_TO_REPO_HOSTNAME/g" $SHARE_CONFIG_CUSTOM
      sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $SHARE_CONFIG_CUSTOM
      mv $SHARE_CONFIG_CUSTOM $CATALINA_HOME/shared/classes/alfresco/web-extension/
    fi

    read -e -p "Install Postgres JDBC Connector${ques} [y/n] " -i "$DEFAULTYESNO" installpg
    if [ "$installpg" = "y" ]; then
      USE_POSTGRESQL=y
      curl -# -O $JDBCPOSTGRESURL/$JDBCPOSTGRES
      mv $JDBCPOSTGRES $CATALINA_HOME/lib
    else
      echo "Skipping install of Postgres JDBC Connector"
    fi
    echo
    read -e -p "Install Mysql JDBC Connector${ques} [y/n] " -i "n" installmy
    if [ "$installmy" = "y" ]; then
      USE_MARIADB=y
      curl -# -L -O $JDBCMYSQLURL/$JDBCMYSQL
      tar xf $JDBCMYSQL
      pushd "$(find . -type d -name "mysql-connector*")"
        mv mysql-connector*.jar $CATALINA_HOME/lib
      popd
    else
      echo "Skipping install of mariaDB JDBC Connector"
    fi
    echog "Finished installing Tomcat"
  else
    echo "Skipping install of Tomcat"
  fi
}

function nginx_install
{
  echo "Nginx can be used as frontend to Tomcat."
  echo "This installation will add config default proxying to Alfresco tomcat."
  echo "The config file also have sample config for ssl."
  echo "You can run Alfresco fine without installing nginx."
  echo "If you prefer to use Apache, install that manually. Or you can use iptables"
  echo "forwarding, sample script in $ALF_HOME/scripts/iptables.sh"

  if [ ! -x "$(command -v nginx)" ]; then
    read -e -p "Install nginx${ques} [y/n] " -i "$DEFAULTYESNO" installnginx
    if [ "$installnginx" = "y" ]; then
      echob "Installing nginx. Fetching packages..."
      sudo apt-get install nginx-full
      sudo systemctl stop nginx
      sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
      sudo cp $TEMPLATES/nginx/nginx.conf /etc/nginx/nginx.conf
      sudo sed -i "s!@@INSTHOME@@!$ALF_HOME!g" /etc/nginx/nginx.conf
      sudo sed -i "s!@@NGINX_LOG@@!$ALF_HOME/logs!g" /etc/nginx/nginx.conf
      sudo cp  $TEMPLATES/nginx/alfresco.conf /etc/nginx/conf.d/alfresco.conf
      sudo sed -i "s!@@INSTHOME@@!$ALF_HOME!g" /etc/nginx/conf.d/alfresco.conf
      sudo sed -i "s!@@NGINX_CACHE@@!$NGINX_CACHE!g" /etc/nginx/nginx.conf
      sudo cp  $TEMPLATES/nginx/alfresco.conf.ssl /etc/nginx/conf.d/alfresco.conf.ssl
      sudo sed -i "s!@@INSTHOME@@!$ALF_HOME!g" /etc/nginx/conf.d/alfresco.conf.ssl
      sudo sed -i "s!@@NGINX_CACHE@@!$NGINX_CACHE!g" /etc/nginx/conf.d/alfresco.conf.ssl
      sudo cp  $TEMPLATES/nginx/basic-settings.conf /etc/nginx/conf.d/basic-settings.conf
      sudo sed -i "s!@@NGINX_LOG@@!$ALF_HOME/logs!g" /etc/nginx/conf.d/basic-settings.conf

      test -d $NGINX_CACHE || mkdir -p $NGINX_CACHE
      # Make the ssl dir as this is what is used in sample config
      test -d /etc/nginx/ssl || sudo mkdir -p /etc/nginx/ssl
      mkdir -p $ALF_HOME/www
      if [ ! -f "$ALF_HOME/www/maintenance.html" ]; then
        echo "Downloading maintenance html page..."
        cp $TEMPLATES/nginx/maintenance.html $ALF_HOME/www/maintenance.html
      fi
      sudo chown -R www-data:root $NGINX_CACHE
      sudo chown -R www-data:$USER $ALF_HOME/www
      sudo chmod 770 $ALF_HOME/www
      find $ALF_HOME/www -type d -exec sudo chmod 770 {} \;
      find $ALF_HOME/www -type f -exec sudo chmod 660 {} \;

      ## Start nginx
      sudo systemctl start nginx
      echo
      echog "Finished installing nginx"
      echo
    fi
  else
    echo "Skipping install of nginx"
  fi
}

function java_install
{
  echo "Install Java JDK."
  echo "This will install OpenJDK 11 version of Java. If you prefer Oracle Java 11 "
  echo "you need to download and install that manually."
  read -e -p "Install OpenJDK${ques} [y/n] " -i "$DEFAULTYESNO" installjdk
  if [ "$installjdk" = "y" ]; then
    echob "Installing OpenJDK..."
    sudo apt-get $APTVERBOSITY install openjdk-11-jre-headless
    echo
    echog "Make sure correct default java is selected!"
    echo
    sudo update-alternatives --config java
    echo
    echog "Finished installing OpenJDK "
    echo
    echob "Setting JAVA_HOME..."
    jhome=$(readlink -f /usr/bin/java)
    expjhome="export JAVA_HOME=${jhome%%/bin/java}"
    echo $expjhome >> $ALF_HOME/.bashrc
    echog "Finished Setting JAVA_HOME "
    echo
  else
    echo "Skipping install of OpenJDK."
    echor "IMPORTANT: You need to install other JDK and adjust paths for the install to be complete"
  fi
}

function libreoffice_install
{
  echo "Install LibreOffice."
  echo "This will download and install the latest LibreOffice from libreoffice.org"
  echo "Newer version of Libreoffice has better document filters, and produce better"
  echo "transformations. If you prefer to use Debian standard packages you can skip"
  echo "this install."
  read -e -p "Install LibreOffice${ques} [y/n] " -i "$DEFAULTYESNO" installibreoffice

  if [ "$installibreoffice" = "y" ]; then

    dpkg -l | grep libreoffice6.4 > /dev/null
    if [ $? -eq 1 ]; then
      curl -# -L -O $LIBREOFFICE
      tar xf LibreOffice*.tar.gz
      cd "$(find . -type d -name "LibreOffice*")"
      cd DEBS
      rm *gnome-integration*.deb &&\
      rm *kde-integration*.deb &&\
      rm *debian-menus*.deb &&\
      sudo dpkg -i *.deb
    fi
    printfb "Installing some support fonts for better transformations..."
    # libxinerama1 libglu1-mesa needed to get LibreOffice 4.4 to work. 
    # Add the libraries that Alfresco mention in documentatinas required.
    ### ttf-mscorefonts-installer 3.8 

    ### Getting from sid repository
    dpkg -l | grep mscorefonts > /dev/null
    if [ $? -eq 1 ]; then
      curl -# -o ttf.deb http://ftp.us.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8_all.deb
      sudo apt-get $APTVERBOSITY install cabextract xfonts-utils fonts-noto fontconfig libcups2 libfontconfig1 libglu1-mesa libice6 libsm6 libxinerama1 libxrender1 libxt6 libcairo2
      sudo dpkg -i ttf.deb
      echog "[OK]"
    fi
    echo
    echog "Finished installing LibreOffice"
    echo
  else
    echo
    echo "Skipping install of LibreOffice"
    echor "If you install LibreOffice/OpenOffice separetely, remember to update alfresco-global.properties"
    echor "Also run: sudo apt-get install ttf-mscorefonts-installer fonts-droid libxinerama1"
    echo
  fi
}

function imagemagick_install
{
  echo "Install ImageMagick."
  echo "This will ImageMagick from Debian packages."
  echo "It is recommended that you install ImageMagick."
  echo "If you prefer some other way of installing ImageMagick, skip this step."
  read -e -p "Install ImageMagick${ques} [y/n] " -i "$DEFAULTYESNO" installimagemagick
  dpkg -l | grep imagemagick > /dev/null
  if [ "$installimagemagick" = "y" ] && [ $? -eq 1 ]; then

    printfb "Installing ImageMagick. Fetching packages..."
    sudo apt-get $APTVERBOSITY install imagemagick ghostscript libgs-dev libjpeg62-turbo libpng16-16
    echog "[OK]"
    if [ "$ISON1604" = "y" ]; then
      echob "Creating symbolic link for ImageMagick-6."
      sudo ln -s /etc/ImageMagick-6 /etc/ImageMagick
    fi
    echo
    echog "Finished installing ImageMagick"
    echo
  else
    echo
    echo "Skipping install of ImageMagick"
    echor "Remember to install ImageMagick later. It is needed for thumbnail transformations."
    echo
  fi
}

function basicsupport_install
{
  echob "Adding basic support files. Always installed if not present."
  # Always add the addons dir and scripts
  mkdir -p $ALF_HOME/addons/war
  mkdir -p $ALF_HOME/addons/share
  mkdir -p $ALF_HOME/addons/alfresco
  if [ ! -f "$ALF_HOME/addons/apply.sh" ]; then
    echo "Downloading apply.sh script..."
    cp  $INST_SOURCE/scripts/apply.sh $ALF_HOME/addons/apply.sh
    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $ALF_HOME/addons/apply.sh 
    chmod u+x $ALF_HOME/addons/apply.sh
  fi
  if [ ! -f "$ALF_HOME/addons/alfresco-mmt.jar" ]; then
    curl -# -o $ALF_HOME/addons/alfresco-mmt.jar $ALFMMTJAR
  fi

  # Add the jar modules dir
  mkdir -p $ALF_HOME/modules/platform
  mkdir -p $ALF_HOME/modules/share

  mkdir -p $ALF_HOME/bin
  if [ ! -f "$ALF_HOME/bin/alfresco-pdf-renderer" ]; then
    echo "Downloading Alfresco PDF Renderer binary (alfresco-pdf-renderer)..."
    curl -# -o alfresco-pdf-renderer.tgz $ALFRESCO_PDF_RENDERER
    tar -xf alfresco-pdf-renderer.tgz -C $ALF_HOME/bin/
  fi
  mkdir -p $ALF_HOME/scripts
  if [ "$USE_MARIADB" = 'y' ]; then
    if [ ! -f "$ALF_HOME/scripts/mariadb.sh" ]; then
      echo "Downloading mariadb.sh install and setup script..."
      cp $INST_SOURCE/scripts/mariadb.sh $ALF_HOME/scripts/mariadb.sh
    fi
  fi
  if [ "$USE_POSTGRESQL" = 'y' ]; then
    if [ ! -f "$ALF_HOME/scripts/postgresql.sh" ]; then
      echo "Downloading postgresql.sh install and setup script..."
      cp $INST_SOURCE/scripts/postgresql.sh $ALF_HOME/scripts/postgresql.sh 
    fi
  fi
  if [ ! -f "$ALF_HOME/scripts/limitconvert.sh" ]; then
    echo "Downloading limitconvert.sh script..."
    cp  $INST_SOURCE/scripts/limitconvert.sh $ALF_HOME/scripts/limitconvert.sh
  fi
  if [ ! -f "$ALF_HOME/scripts/createssl.sh" ]; then
    echo "Downloading createssl.sh script..."
    cp $INST_SOURCE/scripts/createssl.sh $ALF_HOME/scripts/createssl.sh
  fi
  if [ ! -f "$ALF_HOME/scripts/libreoffice.sh" ]; then
    echo "Downloading libreoffice.sh script..."
    cp $INST_SOURCE/scripts/libreoffice.sh $ALF_HOME/scripts/libreoffice.sh
    sed -i "s/@@LOCALESUPPORT@@/$LOCALESUPPORT/g" $ALF_HOME/scripts/libreoffice.sh
  	sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $ALF_HOME/scripts/libreoffice.sh
  fi
  if [ ! -f "$ALF_HOME/scripts/iptables.sh" ]; then
    echo "Downloading iptables.sh script..."
    cp $INST_SOURCE/scripts/iptables.sh $ALF_HOME/scripts/iptables.sh
  fi
  if [ ! -f "$ALF_HOME/scripts/ams.sh" ]; then
    echo "Downloading maintenance shutdown script..."
    cp $INST_SOURCE/scripts/ams.sh $ALF_HOME/scripts/ams.sh
  	sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $ALF_HOME/scripts/ams.sh
  fi
  chmod 755 $ALF_HOME/scripts/*.sh
}

function keystore_install
{
  # Keystore
  mkdir -p $ALF_DATA_HOME/keystore
  # Only check for precesence of one file, assume all the rest exists as well if so.
  if [ ! -f " $ALF_DATA_HOME/keystore/ssl.keystore" ]; then
    echo "Downloading keystore files..."
    curl -# -o $ALF_DATA_HOME/keystore/browser.p12 $KEYSTOREBASE/browser.p12
    curl -# -o $ALF_DATA_HOME/keystore/generate_keystores.sh $KEYSTOREBASE/generate_keystores.sh
    curl -# -o $ALF_DATA_HOME/keystore/keystore $KEYSTOREBASE/keystore
    curl -# -o $ALF_DATA_HOME/keystore/keystore-passwords.properties $KEYSTOREBASE/keystore-passwords.properties
    curl -# -o $ALF_DATA_HOME/keystore/ssl-keystore-passwords.properties $KEYSTOREBASE/ssl-keystore-passwords.properties
    curl -# -o $ALF_DATA_HOME/keystore/ssl-truststore-passwords.properties $KEYSTOREBASE/ssl-truststore-passwords.properties
    curl -# -o $ALF_DATA_HOME/keystore/ssl.keystore $KEYSTOREBASE/ssl.keystore
    curl -# -o $ALF_DATA_HOME/keystore/ssl.truststore $KEYSTOREBASE/ssl.truststore
  fi
}

function wars_install
{
  echo "Install Alfresco war files."
  echo "Download war files and optional addons."
  echo "If you have already downloaded your war files you can skip this step and add "
  echo "them manually."
  echo
  echo "If you use separate Alfresco and Share server, only install the needed for each"
  echo "server. Alfresco Repository will need Share Services if you use Share."
  echo
  echo "This install place downloaded files in the $ALF_HOME/addons and then use the"
  echo "apply.sh script to add them to tomcat/webapps. Se this script for more info."
  read -e -p "Add Alfresco Repository war file${ques} [y/n] " -i "$DEFAULTYESNO" installwar
  if [ "$installwar" = "y" ]; then

    echog "Downloading alfresco war file..."
    curl -# -o $ALF_HOME/addons/war/alfresco.war $ALFREPOWAR

    # Add default alfresco and share modules classloader config files
    cp $TEMPLATES/tomcat/alfresco.xml $CATALINA_HOME/conf/Catalina/localhost/alfresco.xml

    echog "Finished adding Alfresco Repository war file"
  else
    echo "Skipping adding Alfresco Repository war file and addons"
  fi

  read -e -p "Add Share Client war file${ques} [y/n] " -i "$DEFAULTYESNO" installsharewar
  if [ "$installsharewar" = "y" ]; then

    echog "Downloading Share war file..."
    curl -# -o $ALF_HOME/addons/war/share.war $ALFSHAREWAR

    # Add default alfresco and share modules classloader config files
    cp $TEMPLATES/tomcat/share.xml $CATALINA_HOME/conf/Catalina/localhost/share.xml

    echog "Finished adding Share war file"
  else
    echo "Skipping adding Alfresco Share war file"
  fi

  if [ "$installwar" = "y" ] || [ "$installsharewar" = "y" ]; then
    if [ "$installwar" = "y" ]; then
        echor "You must install Share Services if you intend to use Share Client."
        read -e -p "Add Share Services plugin${ques} [y/n] " -i "$DEFAULTYESNO" installshareservices
        if [ "$installshareservices" = "y" ]; then
          echo "Downloading Share Services addon..."
          curl -# -o $ALF_HOME/addons/alfresco/${ALFSHARESERVICES##*/} $ALFSHARESERVICES
        fi
    fi
    read -e -p "Add Google docs integration${ques} [y/n] " -i "$DEFAULTYESNO" installgoogledocs
    if [ "$installgoogledocs" = "y" ]; then
      echo "Downloading Google docs addon..."
      if [ "$installwar" = "y" ]; then
        curl -# -o $ALF_HOME/addons/alfresco/${GOOGLEDOCSREPO##*/} $GOOGLEDOCSREPO
      fi
      if [ "$installsharewar" = "y" ]; then
        curl -# -o $ALF_HOME/addons/share/${GOOGLEDOCSSHARE##*/} $GOOGLEDOCSSHARE
      fi
    fi
  fi
  echo "Install Alfresco Office Services (Sharepoint protocol emulation)."
  echo "This allows you to open and save Microsoft Office documents online."
  echor "This module is not Open Source (Alfresco proprietary)."
  read -e -p "Install Alfresco Office Services integration${ques} [y/n] " -i "n" installssharepoint
  if [ "$installssharepoint" = "y" ]; then
      echog "Installing Alfresco Offices Services bundle..."
      echog "Downloading Alfresco Office Services amp file"
      curl -# -o $ALF_HOME/addons/alfresco/${AOS_AMP##*/} $AOS_AMP
      echog "Downloading _vti_bin.war into tomcat/webapps"
      curl -# -o $ALF_HOME/tomcat/webapps/_vti_bin.war $AOS_VTI
      echog "Downloading ROOT.war into tomcat/webapps"
      curl -# -o $ALF_HOME/tomcat/webapps/ROOT.war $AOS_SERVER_ROOT
  fi
}

function apply_wars
{
  # Install of war and addons complete, apply them to war file
  if [ "$installwar" = "y" ] || [ "$installsharewar" = "y" ] || [ "$installssharepoint" = "y" ]; then
      # Check if Java is installed before trying to apply
      if type -p java; then
          _java=java
      elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
          _java="$JAVA_HOME/bin/java"
          echor "No JDK installed. When you have installed JDK, run "
          echor "$ALF_HOME/addons/apply.sh all"
          echor "to install addons with Alfresco or Share."
      fi
      if [[ "$_java" ]]; then
          $ALF_HOME/addons/apply.sh all
      fi
  fi
}

function solr_install
{
  echo "Install Solr6 Alfresco Search Services indexing engine."
  echo "You can run Solr6 on a separate server, unless you plan to do that you should"
  echo "install the Solr6 indexing engine on the same server as your repository server."
  echor "Alfresco Search Services will be installed without SSL!"
  echor "Configure firewall to block port 8983 or install ssl, see"
  echor "https://docs.alfresco.com/community/tasks/solr6-install.html"
  read -e -p "Install Solr6 indexing engine${ques} [y/n] " -i "$DEFAULTYESNO" installsolr
  if [ "$installsolr" = "y" ]; then

    # Make sure we have unzip available
    sudo apt-get $APTVERBOSITY install unzip

    echog "Downloading Solr6 file..."
    curl -# -o $ALF_HOME/solr6.zip $ASS_DOWNLOAD
    echog "Expanding Solr6 file..."
    pushd $ALF_HOME
      unzip -q solr6.zip
      mv alfresco-search-services solr6
      rm solr6.zip
    popd

    echog "Downloading Solr6 scripts and settings file..."
    sudo cp $TEMPLATES/search/alfresco-search.service /etc/systemd/system/alfresco-search.service
    sudo sed -i "s!@@INSTHOME@@!$ALF_HOME!g" /etc/systemd/system/alfresco-search.service
    cp $TEMPLATES/search/shared.properties $ALF_HOME/solr6/solrhome/conf/shared.properties
    cp $TEMPLATES/search/solr.in.sh $ALF_HOME/solr6/solr.in.sh
    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $ALF_HOME/solr6/solr.in.sh
    chmod u+x $ALF_HOME/solr6/solr.in.sh
    # Enable the service
    sudo systemctl enable alfresco-search.service
    sudo systemctl daemon-reload

    echog "Finished installing Solr6 engine."
    echor "Verify your setting in alfresco-global.properties."
    echo "Set property value index.subsystem.name=solr6"
  else
    echo "Skipping installing Solr6."
    echo "You can always install Solr6 at a later time."
  fi
}

function bart_install
{
  echo "Alfresco BART - Backup and Recovery Tool"
  echo "Alfresco BART is a backup and recovery tool for Alfresco ECM. Is a shell script"
  echo "tool based on Duplicity for Alfresco backups and restore from a local file system,"
  echo "FTP, SCP or Amazon S3 of all its components: indexes, data base, content store "
  echo "and all deployment and configuration files."
  read -e -p "Install B.A.R.T${ques} [y/n] " -i "$DEFAULTYESNO" installbart

  if [ "$installbart" = "y" ]; then
    echog "Installing B.A.R.T"

    mkdir -p $ALF_HOME/scripts/bart
    mkdir -p $ALF_HOME/logs/bart
    BP=$ALF_HOME/scripts/bart/$BART_PROPERTIES
    BE=$ALF_HOME/scripts/bart/$BART_EXECUTE
    cp $TEMPLATES/bart/$BART_PROPERTIES $BP
    cp $INST_SOURCE/scripts/$BART_EXECUTE $BE

    # Update bart settings
    ALFHOMEESCAPED="${ALF_HOME//\//\\/}"
    BARTLOGPATH="$ALF_HOME/logs/bart"
    ALFBRTPATH="$ALF_HOME/scripts/bart"
    INDEXESDIR="\$\{ALF_DIRROOT\}/solr6"
    # Escape for sed
    BARTLOGPATH="${BARTLOGPATH//\//\\/}"
    ALFBRTPATH="${ALFBRTPATH//\//\\/}"
    INDEXESDIR="${INDEXESDIR//\//\\/}"

    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $BP
    sed -i "s!@@INSTHOME@@!$ALF_HOME!g" $BE
    sed -i "s/ALF_INSTALLATION_DIR\=.*/ALF_INSTALLATION_DIR\=$ALFHOMEESCAPED/g" $BP
    sed -i "s/ALFBRT_LOG_DIR\=.*/ALFBRT_LOG_DIR\=$BARTLOGPATH/g" $BP
    sed -i "s/INDEXES_DIR\=.*/INDEXES_DIR\=$INDEXESDIR/g" $BP
    sed -i "s/ALFBRT_PATH\=.*/ALFBRT_PATH\=$ALFBRTPATH/g" $BE

    chmod 700 $BP
    chmod 774 $BE

    # Install dependency
    sudo apt-get $APTVERBOSITY install duplicity
    # Add to cron tab
    tmpfile=/tmp/crontab.tmp
    # add custom entries to crontab
    echo "0 5 * * * $BE backup" >> $tmpfile
    #load crontab from file
    crontab $tmpfile
    # remove temporary file
    rm $tmpfile
    # restart crontab
    sudo systemctl restart cron
    echog "B.A.R.T Cron is installed to run in 5AM every day as the $ALF_USER user"
  fi
}
