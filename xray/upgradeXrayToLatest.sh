#!/bin/bash
#
# Purpose: Xray upgrade - this script is only called from others. 
# Requirements: jq | curl
# Author: Loren Y
#
SCRIPT_DIR=`dirname $0`
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"
XRAY_HOME=$(jq -r '.xray_home' $PARENT_SCRIPT_DIR/json/xrayValues.json)
XRAY_URL=$(jq -r '.xray_url' $PARENT_SCRIPT_DIR/json/xrayValues.json)
XRAY_CREDS=$(jq -r '"\(.username):\(.password)"' $PARENT_SCRIPT_DIR/json/xrayValues.json)
XRAY_DIR=$(jq -r '.xray_dir' $PARENT_SCRIPT_DIR/json/xrayValues.json)
INSTALL_TYPE=$(jq -r '.install_type' $PARENT_SCRIPT_DIR/json/xrayValues.json)

upgrade_xray () {
    echo "Downloading Xray's $INSTALL_TYPE installation..."
    case ${INSTALL_TYPE} in
        docker) 
            curl -sL "https://bintray.com/jfrog/xray/download_file?agree=true&file_path=installer%2F$LATEST_VERSION%2Fxray" -o $XRAY_DIR/xray-$LATEST_VERSION.sh
            chmod +x $XRAY_DIR/xray-$LATEST_VERSION.sh
            $XRAY_DIR/xray-$LATEST_VERSION.sh upgrade
            $XRAY_DIR/xray-$LATEST_VERSION.sh start all
            cp $XRAY_DIR/xray-$LATEST_VERSION.sh $XRAY_DIR/xray
            
            GREENLIGHT=$(curl -su $XRAY_CREDS $XRAY_URL/api/v1/system/ping | jq -r '.status');
            while [ "$GREENLIGHT" != "pong" ]; do
                GREENLIGHT=$(curl -su $XRAY_CREDS $XRAY_URL/api/v1/system/ping | jq -r '.status')
                echo "Time spent waiting for Xray to start:$TIMER seconds..."
                TIMER=$((TIMER + 2))
                sleep 2
                if [ "$TIMER" -gt 60 ]; then
                    echo "Xray $LATEST_VERSION probably failed to start up. Time to check the logs friendo."
                fi
	        done
            if [ "$GREENLIGHT" = "pong" ]; then
                echo "Xray $LATEST_VERSION is up, removing old Xray images..."
                docker rmi docker.bintray.io/jfrog/xray-installer:$MY_VERSION
                docker rmi docker.bintray.io/jfrog/xray-analysis:$MY_VERSION
                docker rmi docker.bintray.io/jfrog/xray-persist:$MY_VERSION
                docker rmi docker.bintray.io/jfrog/xray-indexer:$MY_VERSION
                docker rmi docker.bintray.io/jfrog/xray-server:$MY_VERSION
            fi
            break;;
        *) 
            curl -L "https://bintray.com/jfrog/xray/download_file?agree=true&file_path=xray-$INSTALL_TYPE-$LATEST_VERSION.tar.gz" -o $XRAY_DIR/xray-$INSTALL_TYPE-$LATEST_VERSION.tar.gz
            tar -xf $XRAY_DIR/xray-$INSTALL_TYPE-$LATEST_VERSION.tar.gz -C $XRAY_DIR
            $XRAY_DIR/xray-$INSTALL_TYPE-$LATEST_VERSION/installXray-$INSTALL_TYPE.sh
            break;;
    esac
    
}
MY_VERSION=$(curl -s $XRAY_URL/api/v1/system/version | jq  -r '.xray_version')
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