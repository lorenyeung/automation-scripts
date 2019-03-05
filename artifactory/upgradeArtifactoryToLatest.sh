#!/bin/bash
SCRIPT_DIR=`dirname $0`;
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"
ARTI_CREDS=$(jq -r '"\(.username):\(.apikey)"' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTI_URL=$(jq -r '.arti_url' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INIT_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
if [ "$INIT_CHECK" != "OK" ]; then
    echo "$(date) Artifactory is not running, checking for auto upgrade" | tee -a $PARENT_SCRIPT_DIR/automate.log
        # probably need a check for serviceValues.json
        MY_VERSION=$(jq -r '.artifactory' $PARENT_SCRIPT_DIR/json/serviceValues.json)
        if [ ! -z "$MY_VERSION" ]; then
            echo "$(date) Last version is $MY_VERSION" | tee -a $PARENT_SCRIPT_DIR/automate.log
        else  
	    	echo "Artifactory is not running and serviceValues.json is empty, exiting..." 
	    	exit
        fi
else 
    MY_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/version | jq -r '.version')
fi
LATEST_VERSION=$(curl -s https://api.bintray.com/packages/jfrog/artifactory-pro/jfrog-artifactory-pro-zip/versions/_latest | jq -r '.name')
ARTI_HOME=$(jq -r '.arti_home' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTIS_DIR=$(jq -r '.artis_dir' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INSTALL_TYPE=$(jq -r '.install_type' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
EXTERNAL_DB_JAR=$(jq -r '.external_db_jar' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)

upgrade_artifactory () {
	HA_CHECK=FALSE
        AUTO_CHECK=$(jq -r '.artifactory' $PARENT_SCRIPT_DIR/json/serviceValues.json)
        if [ ! -z "$AUTO_CHECK" ]; then
            UI_CHECK="[]" #assume primary/standalone for now
        else
	    	UI_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/ui/highAvailability)
        fi
        if [ "$UI_CHECK" != "[]" ]; then
			HA_CHECK=TRUE
			echo "$(date) HA Artifactory Cluster detected, performing pre-requisite primary version check.." | tee -a $PARENT_SCRIPT_DIR/automate.log
			PRIMARY_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/ui/highAvailability | jq -r '.[] | select(.role=="Primary") | .version')
			NODE_ROLE=$(grep "primary" $ARTI_HOME/etc/ha-node.properties)
			echo $NODE_ROLE
			if [[ "$NODE_ROLE" = *"false"* ]] && [ "$MY_VERSION" = "$PRIMARY_VERSION" ]; then
				echo "$(date) It looks like you're trying to upgrade the member node ($MY_VERSION) first, please upgrade the primary first" | tee -a $PARENT_SCRIPT_DIR/automate.log
				exit
			fi
		else
            echo "$(date) Standalone Artifactory detected, continuing.." | tee -a $PARENT_SCRIPT_DIR/automate.log
	fi
	# TODO expired license check
	# TODO maybe another check for linux commands before the wget
        echo "$(date) Stopping Artifactory $MY_VERSION..." | tee -a $PARENT_SCRIPT_DIR/automate.log
	case ${INSTALL_TYPE} in
        Zip ) 
			$ARTI_HOME/bin/artifactory.sh stop;
			echo "$(date) Downloading Artifactory $LATEST_VERSION from Bintray..." | tee -a $PARENT_SCRIPT_DIR/automate.log
			wget "https://dl.bintray.com/jfrog/artifactory-pro/org/artifactory/pro/jfrog-artifactory-pro/$LATEST_VERSION/jfrog-artifactory-pro-$LATEST_VERSION.zip" -O $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip
			echo "$(date) Unzipping Artifactory $LATEST_VERSION" | tee -a $PARENT_SCRIPT_DIR/automate.log
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
		echo "$(date) Backing up JDBC Driver $EXTERNAL_DB_JAR" | tee -a $PARENT_SCRIPT_DIR/automate.log
		cp $EXTERNAL_DB_JAR $ARTIS_DIR	
	fi
        echo "$(date) Upgrading Artifactory $MY_VERSION to $LATEST_VERSION..." | tee -a $PARENT_SCRIPT_DIR/automate.log
	case ${INSTALL_TYPE} in
        Zip ) 		
			#TODO HA zip upgrade - need to consider server.xml, artifactory.default file for zip install.
			rm -r $ARTI_HOME/bin/ $ARTI_HOME/misc/ $ARTI_HOME/webapps/ $ARTI_HOME/tomcat/
			cp -r $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/bin $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/misc $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/webapps $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/tomcat $ARTI_HOME/
			if [ "$EXTERNAL_DB_JAR" != "none" ]; then
                            echo "$(date) Restoring JDBC Driver $EXTERNAL_DB_JAR" | tee -a $PARENT_SCRIPT_DIR/automate.log
				JAR_FILE=$(basename $EXTERNAL_DB_JAR)
				cp $ARTIS_DIR/$JAR_FILE $ARTI_HOME/tomcat/lib/
			fi
                        echo "$(date) Starting Artifactory $LATEST_VERSION..." | tee -a $PARENT_SCRIPT_DIR/automate.log
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
				echo "$(date) Restoring JDBC Driver $EXTERNAL_DB_JAR" | tee -a $PARENT_SCRIPT_DIR/automate.log
				JAR_FILE=$(basename $EXTERNAL_DB_JAR)
				cp $ARTIS_DIR/$JAR_FILE /opt/jfrog/artifactory/tomcat/lib/	
			fi
			echo "$(date) Starting Artifactory $LATEST_VERSION..." | tee -a $PARENT_SCRIPT_DIR/automate.log
			systemctl start artifactory.service;
			rm $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.rpm
			;;
    esac

	
    echo "$(date) Pinging Artifactory..." | tee -a $PARENT_SCRIPT_DIR/automate.log
	GREENLIGHT=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
	TIMER=0
	while [ "$GREENLIGHT" != "OK" ]; do
		GREENLIGHT=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
                echo "$(date) Time spent waiting for Artifactory to start:$TIMER seconds..." | tee -a $PARENT_SCRIPT_DIR/automate.log
		TIMER=$((TIMER + 2))
		sleep 2
	done
	echo "$(date) Artifactory Status: $GREENLIGHT" | tee -a $PARENT_SCRIPT_DIR/automate.log
	if [ "$GREENLIGHT" = "OK" ]; then
		if [ "$BACKUP_CHECK" = "TRUE" ]; then
			echo "Removing backup"
			rm -r $ARTIS_DIR/artifactory-pro-latest-backup/
		fi
		echo "$(date) Upgrade to Artifactory $LATEST_VERSION complete." | tee -a $PARENT_SCRIPT_DIR/automate.log
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