#!/bin/bash
#
# Purpose: Xray upgrade - this script is only called from others. 
# Requirements: jq | curl
# Author: Loren Y
#
upgrade_xray () {
    echo "Downloading Xray $LATEST_VERSION's docker script..."
    curl -sL "https://bintray.com/jfrog/xray/download_file?agree=true&file_path=installer%2F$LATEST_VERSION%2Fxray" -o $XRAY_DIR/xray-$LATEST_VERSION.sh
    chmod +x $XRAY_DIR/xray-$LATEST_VERSION.sh
    $XRAY_DIR/xray-$LATEST_VERSION.sh upgrade
    $XRAY_DIR/xray-$LATEST_VERSION.sh start all
    cp $XRAY_DIR/xray-$LATEST_VERSION.sh $XRAY_DIR/xray
    
    sleep 10
    API_PING=$(curl -u $XRAY_USER:$XRAY_PASS $XRAY_URL/api/v1/system/ping | jq -r '.status');
    if [ "$API_PING" = "pong" ]; then
    	echo "Xray $LATEST_VERSION is up, removing old Xray images..."
	docker rmi docker.bintray.io/jfrog/xray-installer:$MY_VERSION
	docker rmi docker.bintray.io/jfrog/xray-analysis:$MY_VERSION
	docker rmi docker.bintray.io/jfrog/xray-persist:$MY_VERSION
	docker rmi docker.bintray.io/jfrog/xray-indexer:$MY_VERSION
	docker rmi docker.bintray.io/jfrog/xray-server:$MY_VERSION
    else
    	echo "Xray $LATEST_VERSION probably failed to start up. Time to check the logs friendo."
    fi
}
MY_VERSION=$(curl -s http://localhost:8000/api/v1/system/version | jq  -r '.xray_version')
LATEST_VERSION=$(curl -s https://api.bintray.com/packages/jfrog/xray/xray-docker/versions/_latest | jq -r '.name')

if [ "$MY_VERSION" = "$LATEST_VERSION" ]; then
    echo "You are on Xray $MY_VERSION, the latest is $LATEST_VERSION, no upgrade needed.";
    exit
fi
if [ "$MY_VERSION" != "$LATEST_VERSION" ]; then
    echo "You are on Xray $MY_VERSION, the latest is $LATEST_VERSION, would you like to upgrade now?";
    select yn in "Yes" "No" "Different Version"; do
        case $yn in
            Yes ) upgrade_xray; break;;
            No ) echo "Exiting..." ; exit;;
	    "Different Version" ) echo "Desired Xray Version:"; read LATEST_VERSION; upgrade_xray; break;;
    	esac
    done
fi