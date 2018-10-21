#!/bin/bash
echo "upgradeArtifactoryToLatest script version 1.0.0"
SCRIPT_DIR=`dirname $0`; 
ARTI_CREDS=$(jq -r '"\(.username):\(.apikey)"' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTI_URL=$(jq -r '.arti_url' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INIT_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
if [ "$INIT_CHECK" != "OK" ]
    then
        echo "Artifactory is not running, exiting..."
		exit
fi

MY_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/version | jq -r '.version')
LATEST_VERSION=$(curl -s https://api.bintray.com/packages/jfrog/artifactory-pro/jfrog-artifactory-pro-zip/versions/_latest | jq -r '.name')
ARTI_HOME=$(jq -r '.arti_home' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTIS_DIR=$(jq -r '.artis_dir' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INSTALL_TYPE=$(jq -r '.install_type' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)

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

	echo "Stopping Artifactory $MY_VERSION..."
	if [ "$INSTALL_TYPE" = "Zip" ]; then
		$ARTI_HOME/bin/artifactory.sh stop
	fi
	if [ "$INSTALL_TYPE" = "RPM" ]; then 
		systemctl stop artifactory.service
	fi
	STOP_CHECK=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)
	if [ "$STOP_CHECK" = "OK" ]
        then
            echo "Artifactory did not stop properly, exiting..."
            exit
	fi	
	echo "Downloading Artifactory $LATEST_VERSION from Bintray..."
	if [ "$INSTALL_TYPE" = "Zip" ]; then
		wget "https://dl.bintray.com/jfrog/artifactory-pro/org/artifactory/pro/jfrog-artifactory-pro/$LATEST_VERSION/jfrog-artifactory-pro-$LATEST_VERSION.zip" -O $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip
		echo "Unzipping Artifactory $LATEST_VERSION"
		unzip -qq $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip -d $ARTIS_DIR/
	fi
	if [ "$INSTALL_TYPE" = "RPM" ]; then
		wget "https://dl.bintray.com/jfrog/artifactory-pro-rpms/org/artifactory/pro/rpm/jfrog-artifactory-pro/$LATEST_VERSION/jfrog-artifactory-pro-$LATEST_VERSION.rpm" -O $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.rpm
    	fi
	echo "Do you want to temporarily back up Artifactory before upgrading? This may take a while but is safer."
    BACKUP_CHECK=FALSE
    select yn in "Yes" "No"; do
    	    case $yn in
        		Yes ) BACKUP_CHECK=TRUE; echo "Backing up Artifactory $MY_VERSION to $ARTIS_DIR/artifactory-pro-latest-backup"; cp -r $ARTI_HOME/ $ARTIS_DIR/artifactory-pro-latest-backup/; break;;
        		No ) echo "I hope you know what you are doing." ; break;;
    		esac
		done
	
	echo "Upgrading Artifactory $MY_VERSION to $LATEST_VERSION..."
	if [ "$INSTALL_TYPE" = "Zip" ]; then
		rm -r $ARTI_HOME/bin/ $ARTI_HOME/misc/ $ARTI_HOME/webapps/ $ARTI_HOME/tomcat/
		cp -r $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/bin $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/misc $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/webapps $ARTIS_DIR/artifactory-pro-$LATEST_VERSION/tomcat $ARTI_HOME/
	fi
	if [ "$INSTALL_TYPE" = "RPM" ]; then
		rpm -U $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.rpm
	fi
        echo "Starting Artifactory $LATEST_VERSION..."
	if [ "$INSTALL_TYPE" = "Zip" ]; then
		$ARTI_HOME/bin/artifactory.sh start
		rm -r $ARTIS_DIR/artifactory-pro-$LATEST_VERSION
		rm $ARTIS_DIR/jfrog-artifactory-pro-$LATEST_VERSION.zip
	fi
	if [ "$INSTALL_TYPE" = "RPM" ]; then
		systemctl start artifactory.service
	fi
	
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
	if [ "$GREENLIGHT" = "OK" ]
		then
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

if [ "$MY_VERSION" = "$LATEST_VERSION" ]
	then
		echo "You are on $MY_VERSION, the latest is $LATEST_VERSION, no upgrade needed.";
		exit
fi
if [ "$MY_VERSION" != "$LATEST_VERSION" ]
	then
		echo "You are on $MY_VERSION, the latest is $LATEST_VERSION, would you like to upgrade now?";
		select yn in "Yes" "No" "Different Version"; do
    	    case $yn in
        		Yes ) upgrade_artifactory; break;;
        		No ) echo "Exiting..." ; exit;;
				"Different Version" ) echo "Desired Artifactory Version:"; read LATEST_VERSION; upgrade_artifactory; break;;
    		esac
		done
fi
