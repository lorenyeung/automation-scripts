#!/bin/bash
SCRIPT_DIR=`dirname $0`;
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"
ARTI_CREDS=$(jq -r '"\(.username):\(.apikey)"' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTI_URL=$(jq -r '.arti_url' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INIT_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
if [ "$INIT_CHECK" != "OK" ]; then
	echo "Artifactory is not running, exiting..."
	exit
fi

MY_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/version | jq -r '.version')
LATEST_VERSION=$(curl -s https://api.bintray.com/packages/jfrog/artifactory-pro/jfrog-artifactory-pro-zip/versions/_latest | jq -r '.name')
ARTI_HOME=$(jq -r '.arti_home' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTIS_DIR=$(jq -r '.artis_dir' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INSTALL_TYPE=$(jq -r '.install_type' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
EXTERNAL_DB_JAR=$(jq -r '.external_db_jar' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)

upgrade_artifactory () {
	HA_CHECK=FALSE
	UI_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/ui/highAvailability)
	if [ "$UI_CHECK" != "[]" ]; then
		HA_CHECK=TRUE
		echo "HA Artifactory Cluster detected, performing pre-requisite primary version check.."
		PRIMARY_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/ui/highAvailability | jq -r '.[] | select(.role=="Primary") | .version')
		NODE_ROLE=$(grep "primary" $ARTI_HOME/etc/ha-node.properties)
		echo $NODE_ROLE
		if [[ "$NODE_ROLE" = *"false"* ]] && [ "$MY_VERSION" = "$PRIMARY_VERSION" ]; then
			echo "It looks like you're trying to upgrade the member node ($MY_VERSION) first, please upgrade the primary first"
			exit
		fi
	else
		echo "Standalone Artifactory detected, continuing.."
	fi
	# TODO expired license check
	# TODO maybe another check for linux commands before the wget
	echo "Stopping Artifactory $MY_VERSION..."
	case ${INSTALL_TYPE} in
        Zip ) 
			$ARTI_HOME/bin/artifactory.sh stop;
			echo "Downloading Artifactory $LATEST_VERSION from Bintray..."
			wget "https://dl.bintray.com/jfrog/artifactory-pro/org/artifactory/pro/jfrog-artifactory-pro/$LATEST_VERSION/jfrog-artifactory-pro-$LATEST_VERSION.zip" -O $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip
			echo "Unzipping Artifactory $LATEST_VERSION"
			unzip -qq $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip -d $ARTIS_DIR/
			;;
        Service ) echo "Currently not supported"; exit;;
        Docker ) echo "Currently not supported"; exit;;
        Debian ) service artifactory stop; exit;;
        RPM ) 
			systemctl stop artifactory.service; 
			wget "https://dl.bintray.com/jfrog/artifactory-pro-rpms/org/artifactory/pro/rpm/jfrog-artifactory-pro/$LATEST_VERSION/jfrog-artifactory-pro-$LATEST_VERSION.rpm" -O $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.rpm
			;;
    esac
	STOP_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
	if [ "$STOP_CHECK" = "OK" ]; then
		echo "Artifactory did not stop properly, exiting..."
		exit
	fi	
	echo "Do you want to temporarily back up Artifactory before upgrading? This may take a while but is safer."
    BACKUP_CHECK=FALSE
    select yn in "Yes" "No"; do
		case $yn in
			Yes) 
				BACKUP_CHECK=TRUE; 
				echo "Backing up Artifactory $MY_VERSION to $ARTIS_DIR/artifactory-pro-latest-backup";
				mkdir $ARTIS_DIR/artifactory-pro-latest-backup
				curl -su $ARTI_CREDS $ARTI_URL/api/export/system > $SCRIPT_DIR/export-settings.json 
				sed -i '' "s|/export/path|$ARTIS_DIR/artifactory-pro-latest-backup|" $SCRIPT_DIR/export-settings.json
				# cat $SCRIPT_DIR/export-settings.json # for debugging purposes
				curl -X POST -su $ARTI_CREDS $ARTI_URL/api/export/system -H "Content-Type: application/json" -T $SCRIPT_DIR/export-settings.json 
				;;
			No)
				echo "I hope you know what you are doing.";
				break;
				;;
		esac
	done
	if [ "$EXTERNAL_DB_JAR" != "none" ]; then
		echo "Backing up JDBC Driver $EXTERNAL_DB_JAR"
		cp $EXTERNAL_DB_JAR $ARTIS_DIR	
	fi
	echo "Upgrading Artifactory $MY_VERSION to $LATEST_VERSION..."
	case ${INSTALL_TYPE} in
        Zip ) 
			echo "STOP HERE"
			exit 
			#TODO HA zip upgrade - need to consider server.xml, artifactory.default file for zip install.
			rm -r $ARTI_HOME/bin/ $ARTI_HOME/misc/ $ARTI_HOME/webapps/ $ARTI_HOME/tomcat/
			cp -r $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/bin $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/misc $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/webapps $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/tomcat $ARTI_HOME/
			 echo "Starting Artifactory $LATEST_VERSION..."
			if [ "$EXTERNAL_DB_JAR" != "none" ]; then
				echo "Restoring JDBC Driver $EXTERNAL_DB_JAR"
				JAR_FILE=$(basename $EXTERNAL_DB_JAR)
				cp $ARTIS_DIR/$JAR_FILE $ARTI_HOME/tomcat/lib/
			fi
			$ARTI_HOME/bin/artifactory.sh start
			rm -r $ARTIS_DIR/artifactory-pro-$LATEST_VERSION
			rm $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip
			;;
        Service ) echo "Currently not supported"; exit;;
        Docker ) echo "Currently not supported"; exit;;
        Debian ) echo "Currently not supported"; exit;;
        RPM ) 
			rpm -U $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.rpm
			if [ "$EXTERNAL_DB_JAR" != "none" ]; then
				echo "Restoring JDBC Driver $EXTERNAL_DB_JAR"
				JAR_FILE=$(basename $EXTERNAL_DB_JAR)
				cp $ARTIS_DIR/$JAR_FILE /opt/jfrog/artifactory/tomcat/lib/	
			fi
			echo "Starting Artifactory $LATEST_VERSION..."
			systemctl start artifactory.service;
			rm $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.rpm
			;;
    esac

	
	echo "Pinging Artifactory..."
	GREENLIGHT=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
	TIMER=0
	while [ "$GREENLIGHT" != "OK" ]; do
		GREENLIGHT=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
		echo "Time spent waiting for Artifactory to start:$TIMER seconds..."
		TIMER=$((TIMER + 2))
		sleep 2
	done
	echo "Artifactory Status: $GREENLIGHT"
	if [ "$GREENLIGHT" = "OK" ]; then
		if [ "$BACKUP_CHECK" = "TRUE" ]; then
			echo "Removing backup"
			rm -r $ARTIS_DIR/artifactory-pro-latest-backup/
		fi
		echo "Upgrade to Artifactory $LATEST_VERSION complete."
		if [ "$HA_CHECK" = "TRUE" ]; then
			echo "Nodes upgraded to $LATEST_VERSION:"
			curl -su $ARTI_CREDS $ARTI_URL/ui/highAvailability | jq -r '.[] | select(.version=="'$LATEST_VERSION'") | "\(.id) \(.role) \(.version)"'
			echo "Nodes left:"
			curl -su $ARTI_CREDS $ARTI_URL/ui/highAvailability | jq -r '.[] | select(.version!="'$LATEST_VERSION'") | "\(.id) \(.role) \(.version)"'
		fi
	fi
}

if [ "$MY_VERSION" = "$LATEST_VERSION" ]; then
	echo "You are on $MY_VERSION, the latest is $LATEST_VERSION, no upgrade needed.";
	exit
fi
if [ "$MY_VERSION" != "$LATEST_VERSION" ]; then
	echo "You are on $MY_VERSION, the latest is $LATEST_VERSION, would you like to upgrade now?";
	select yn in "Yes" "No" "Different Version"; do
		case $yn in
			Yes ) 
				upgrade_artifactory;;
			No ) 
				echo "Exiting..." ; exit;;
			"Different Version" )
				while true; do
					echo "Enter desired Artifactory Version:"; 
					read LATEST_VERSION;
					VERSION_EXISTS=$(curl -i https://dl.bintray.com/jfrog/artifactory-pro/org/artifactory/pro/jfrog-artifactory-pro/$LATEST_VERSION/jfrog-artifactory-pro-$LATEST_VERSION.zip)
					if [[ $VERSION_EXISTS == *"404"* ]]; then
						echo "$LATEST_VERSION does not exist on Bintray. Please try again."
					else
						break;
					fi
				done
				upgrade_artifactory
				;;
		esac
	done
fi