#!/bin/bash

# first time set up config function - can use it to test if its ran before
# otherwise run on start up - (store current version in json - if manual upgrade is ran
# need to update the JSON)
# {"services": [ "artifactory":"X.X.X", "xray":"X.X.X", "continue adding services":"" ] }

SCRIPT_DIR=`dirname $0`
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"
ARTI_SET="false"
XRAY_SET="false"

if [ -f $PARENT_SCRIPT_DIR/json/artifactoryValues.json ]; then
    ARTI_CREDS=$(jq -r '"\(.username):\(.apikey)"' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
    ARTI_URL=$(jq -r '.arti_url' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
    ARTI_SET="true"
fi
if [ -f $PARENT_SCRIPT_DIR/json/xrayValues.json ]; then
    XRAY_URL=$(jq -r '.xray_url' $PARENT_SCRIPT_DIR/json/xrayValues.json)
    XRAY_CREDS=$(jq -r '"\(.username):\(.password)"' $PARENT_SCRIPT_DIR/json/xrayValues.json)
    XRAY_SET="true"
fi
setup_config() {
    if [ ! -f $PARENT_SCRIPT_DIR/json/serviceValues.json ]; then
        SCRIPT_VERSION=$(jq -r .script_version $PARENT_SCRIPT_DIR/metadata.json)
        echo "Welcome to Loren's Automatic service upgrade script. You're on version $SCRIPT_VERSION."
        echo "I could not find $PARENT_SCRIPT_DIR/json/serviceValues.json, generating:"
        declare -a services;
        select install_type in "Artifactory" "Xray" "Finish"; do
            case $install_type in
                Artifactory ) 
                    if [ "$ARTI_SET" = "true" ]; then
                        REST_ARTI_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/version | jq -r '.version')
                        
                        else
                            REST_ARTI_VERSION="None found"
                    fi
                    while true; do
                    echo "Enter Artifactory Version ($REST_ARTI_VERSION):"
                    read arti_version
                    arti_version="${arti_version:=$REST_ARTI_VERSION}"
		    VERSION_EXISTS=$(curl -si https://dl.bintray.com/jfrog/artifactory-pro/org/artifactory/pro/jfrog-artifactory-pro/$arti_version/jfrog-artifactory-pro-$arti_version.zip)
                    if [[ $VERSION_EXISTS == *"404"* ]]; then
                    	echo "$arti_version does not exist on Bintray. Please try again."
                    else
                        break;
                    fi
                    done
                    services+=("Artifactory: $arti_version")
                    echo "added artifactory $arti_version";
                    ;;
                Xray )
                    if [ "$XRAY_SET" = "true" ]; then
                        REST_XRAY_VERSION=$(curl -s $XRAY_URL/api/v1/system/version | jq  -r '.xray_version')
                        else
                            REST_XRAY_VERSION="None found"
                    fi
                    while true; do
                        echo "Enter Xray Version ($REST_XRAY_VERSION):"
                        read xray_version
                        xray_version="${xray_version:=$REST_XRAY_VERSION}"
                        VERSION_EXISTS=$(curl -si http://dl.bintray.com/jfrog/xray/installer/$xray_version/)
                        if [[ $VERSION_EXISTS == *"404"* ]]; then
                            echo "$xray_version does not exist on Bintray. Please try again."
                        else
                            break;
                        fi
                    done
                    services+=("Xray: $xray_version")
                    echo "Added Xray $xray_version";
                    ;;
                Finish ) 
                break;
                ;;
            esac
        done

        echo ${services[@]}
        echo -e "{\"artifactory\":\""$arti_version"\", \"xray\":\""$xray_version"\"}" > $PARENT_SCRIPT_DIR/json/serviceValues.json
    fi
}

upgrade() {
    echo "$(date) Checking if an upgrade is needed" > $PARENT_SCRIPT_DIR/automate.log | tee -a $PARENT_SCRIPT_DIR/automate.log
    LATEST_ARTI_VERSION=$(curl -s https://api.bintray.com/packages/jfrog/artifactory-pro/jfrog-artifactory-pro-zip/versions/_latest | jq -r '.name')
    MY_ARTI_VERSION=$(jq -r '.artifactory' $PARENT_SCRIPT_DIR/json/serviceValues.json)
    LATEST_XRAY_VERSION=$(curl -s https://api.bintray.com/packages/jfrog/xray/xray-docker/versions/_latest | jq -r '.name')
    MY_XRAY_VERSION=$(jq -r '.xray' $PARENT_SCRIPT_DIR/json/serviceValues.json)
    
    if [ "$MY_ARTI_VERSION" != "$LATEST_ARTI_VERSION" ] && [ ! -z "$MY_ARTI_VERSION" ]; then
        echo "$(date) Upgrading Artifactory from $MY_ARTI_VERSION to $LATEST_ARTI_VERSION" | tee -a $PARENT_SCRIPT_DIR/automate.log
        printf "1\n2\n" | $PARENT_SCRIPT_DIR/artifactory/upgradeArtifactoryToLatest.sh;
    fi
    if [ "$MY_XRAY_VERSION" != "$LATEST_XRAY_VERSION" ] && [ ! -z "$MY_XRAY_VERSION" ]; then
        echo "$(date) Upgrading Xray from $MY_XRAY_VERSION to $LATEST_XRAY_VERSION" | tee -a $PARENT_SCRIPT_DIR/automate.log
        printf "1\n" | $PARENT_SCRIPT_DIR/xray/upgradeXrayToLatest.sh;
    fi
}

update_versions() {
    MY_ARTI_VERSION=$(jq -r '.artifactory' $PARENT_SCRIPT_DIR/json/serviceValues.json)
    MY_XRAY_VERSION=$(jq -r '.xray' $PARENT_SCRIPT_DIR/json/serviceValues.json)

    if [ ! -z "$MY_ARTI_VERSION" ]; then
        NEW_ARTI_VERSION=$(curl -su $ARTI_CREDS $ARTI_URL/api/system/version | jq -r '.version')
        echo "$(date) Updating Artifactory version to $NEW_ARTI_VERSION in serviceValues.json" | tee -a $PARENT_SCRIPT_DIR/automate.log
        echo "$(jq --arg version "$NEW_ARTI_VERSION" -r '.artifactory |= $version' $PARENT_SCRIPT_DIR/json/serviceValues.json)" > $PARENT_SCRIPT_DIR/json/serviceValues.json
    fi
        if [ ! -z "$MY_XRAY_VERSION" ]; then
        NEW_XRAY_VERSION=$(curl -s $XRAY_URL/api/v1/system/version | jq  -r '.xray_version')
        echo "$(date) Updating Xray version to $NEW_XRAY_VERSION in serviceValues.json" | tee -a $PARENT_SCRIPT_DIR/automate.log
        echo "$(jq --arg version "$NEW_XRAY_VERSION" -r '.xray |= $version' $PARENT_SCRIPT_DIR/json/serviceValues.json)" > $PARENT_SCRIPT_DIR/json/serviceValues.json
    fi
}

setup_config
upgrade
update_versions