#!/bin/bash
#
# Purpose: Script upgrade - this script is only called from others. 
# Requirements: jq | curl
# Author: Loren Y
#

SCRIPT_DIR=`dirname $0`
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"
SCRIPT_VERSION=$(jq -r .script_version $PARENT_SCRIPT_DIR/metadata.json)

check_script() {
    curl -s https://api.github.com/repos/lorenyeung/automation-scripts/releases/latest > $SCRIPT_DIR/.latestVersion.txt
    LATEST_SCRIPT_VERSION=$(jq -r '.tag_name' $SCRIPT_DIR/.latestVersion.txt)
    LATEST_SCRIPT_TAG=$(jq -r '.name' $SCRIPT_DIR/.latestVersion.txt)
    if [ "$SCRIPT_VERSION" = "$LATEST_SCRIPT_VERSION" ]; then
        echo "You are on the latest version, which is $SCRIPT_VERSION."
    else
        echo "You are on $SCRIPT_VERSION, the latest script version is $LATEST_SCRIPT_VERSION. Would you like to upgrade?"
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) 
                    echo "Downloading $LATEST_SCRIPT_VERSION";
                    LATEST_SCRIPT_DL=$(jq -r '.tarball_url' $SCRIPT_DIR/.latestVersion.txt)
                    curl -sL https://github.com/lorenyeung/automation-scripts/archive/$LATEST_SCRIPT_VERSION.tar.gz -o "$SCRIPT_DIR/download-$LATEST_SCRIPT_VERSION.tar.gz"
                    echo "Extracting"
                    echo $PARENT_SCRIPT_DIR $PARENT2_SCRIPT_DIR 
                    tar -xf $SCRIPT_DIR/download-$LATEST_SCRIPT_VERSION.tar.gz -C $PARENT2_SCRIPT_DIR/
                    cp -r $PARENT_SCRIPT_DIR/json $PARENT2_SCRIPT_DIR/automation-scripts-$LATEST_SCRIPT_TAG/json
                    echo "Last step: $ rm -r $PARENT_SCRIPT_DIR && mv $PARENT2_SCRIPT_DIR/automation-scripts-$LATEST_SCRIPT_TAG $PARENT_SCRIPT_DIR, and open a new shell :)"
                    break;;
                No ) echo "welp" ; break;;
            esac
        done
    fi
    rm $SCRIPT_DIR/.latestVersion.txt
}

check_script