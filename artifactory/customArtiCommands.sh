#!/bin/bash
#
# Purpose: Custom Artifactory Commands Master Script
# Requirements: jq | curl | wget | Artifactory credentials
# Author: Loren Y
#

SCRIPT_DIR=`dirname $0`
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"

#logging mechanism
__VERBOSE=$3
if [ -z "$__VERBOSE" ];then
    __VERBOSE=8
fi
case "$3" in
    warning)
        __VERBOSE=4;;
    info)
        __VERBOSE=6;;
    debug)
        __VERBOSE=7;;
    trace)
        __VERBOSE=8;;
esac

declare -a LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="critical" [3]="error" [4]="warning" [5]="notice" [6]="info" [7]="debug" [8]="trace")
function .log () {
    local LEVEL=${1}
    shift
    if [ ${__VERBOSE} -ge ${LEVEL} ]; then
        tput setaf $LEVEL
        case  "$LEVEL" in
            0)
                tput setaf 1;;
            1)
                tput setaf 1;;
            2)
                tput setaf 1;;
            3)
                tput setaf 1;;
            4)
                tput setaf 3;;
            5)
                tput setaf 8;;
            6)
                tput setaf 8;;
            7)
                tput setaf 0;;
            8)
                tput setaf 4;;
        esac
        echo "[${LOG_LEVELS[$LEVEL]}]" "$@"
        tput sgr0
        CURL_SILENT="Lv"
    fi
}

start_artifactory () {
    case ${INSTALL_TYPE} in
        Zip ) $ARTI_HOME/bin/artifactory.sh start; break;;
        Service ) echo "Currently not supported"; exit;;
        Docker ) echo "Currently not supported" ; exit;;
        Debian ) service artifactory start; exit;;
        RPM ) systemctl start artifactory.service; break;;
    esac
}

stop_artifactory () {
    case ${INSTALL_TYPE} in
        Zip ) $ARTI_HOME/bin/artifactory.sh stop; break;;
        Service ) echo "Currently not supported"; exit;;
        Docker ) echo "Currently not supported" ; exit;;
        Debian ) service artifactory stop; exit;;
        RPM ) systemctl stop artifactory.service; break;;
    esac
}

function set_up () {
    while true; do
        echo "Enter your Artifactory URL (e.g. http://localhost:8081/artifactory):"
        read arti_url
        if [ "$(curl -s $arti_url/api/system/ping)" != "OK" ]; then
            echo "Artifactory doesn't look to be either running or reachable from here."
        else
            break
        fi
    done
    while true; do
        echo "Enter your $arti_url username:"
        read username
        echo "Enter your $arti_url password:"
        read -s password
        echo "Getting API key..."
        apikey=$(curl -su $username:$password $arti_url/api/security/apiKey)
        if [ "${#apikey}" == "2" ]; then
            echo "You probably don't have an API Key. Generating API key.."
            apikey=$(curl -vvv -u $username:$password -XPOST $arti_url/api/security/apiKey)
        fi
        password="clear"
        if [ "${#apikey}" != "86" ] ; then
            echo "Oh no. $(echo $apikey | jq -r '.errors[] | .message')"
        else
            break
        fi
    done
    while true; do
        echo "Enter your \$ARTIFACTORY_HOME location (e.g. /Users/loreny/artifactory/artifactory-pro-latest):"
        read arti_home
        if [ "$arti_home" != "/" ]; then
            arti_home=$(echo $arti_home | sed 's:/*$::')
        fi
        if [ ! -d "$arti_home" ]; then
            echo "$arti_home doesnt exist."
        else
            break
        fi
    done
    while true; do
        echo "Enter your Artifactory Downloads Directory location (e.g. /Users/loreny/artifactory):"
        read artis_dir
        if [ "$artis_dir" != "/" ]; then
            artis_dir=$(echo $artis_dir | sed 's:/*$::')
        fi
        if [ ! -d "$artis_dir" ]; then
            echo "$artis_dir doesnt exist."
        else
            break
        fi
    done

    echo "Select your Artifactory installation type:"
    select install_type in "Zip" "Service" "Docker" "Debian" "RPM"; do
        case $install_type in
            Zip ) break;;
                Service ) echo "Currently not supported"; exit;;
                Docker ) echo "Currently not supported" ; exit;;
            Debian ) echo "Currently not supported"; exit;;
            RPM ) break;;
        esac
    done
    echo "Creating $PARENT_SCRIPT_DIR/json/artifactoryValues.json"
    echo -e "{\"username\":\""$username"\", \"apikey\":\""$(echo $apikey | jq -r '.apiKey')"\", \"arti_home\":\""$arti_home"\", \"arti_url\":\""$arti_url"\", \"artis_dir\":\""$artis_dir"\", \"install_type\":\""$install_type"\"}" > $PARENT_SCRIPT_DIR/json/artifactoryValues.json
}

if [ ! -d $PARENT_SCRIPT_DIR/json ]; then
    mkdir $PARENT_SCRIPT_DIR/json
fi

if [ ! -f $PARENT_SCRIPT_DIR/json/artifactoryValues.json ]; then
    SCRIPT_VERSION=$(jq -r .script_version $PARENT_SCRIPT_DIR/metadata.json)
    echo "Welcome to Loren's Custom Artifactory commands master script. Please ensure that anonymous access is enabled. You're on version $SCRIPT_VERSION. Creating $PARENT_SCRIPT_DIR/json/..."
    $PARENT_SCRIPT_DIR/common/installPrerequisites.sh
    echo "I could not find $PARENT_SCRIPT_DIR/json/artifactoryValues.json, generating:"
    set_up
fi

ARTI_HOME=$(jq -r '.arti_home' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTI_URL=$(jq -r '.arti_url' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
ARTI_CREDS=$(jq -r '"\(.username):\(.apikey)"' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
apikey=$(jq -r '.apikey' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
INSTALL_TYPE=$(jq -r '.install_type' $PARENT_SCRIPT_DIR/json/artifactoryValues.json)
.log 7 "values_precheck_fn:apikey length value: ${#apikey}"
if [ "$(curl -s $ARTI_URL/api/system/ping)" != "OK" ]; then
    echo "Artifactory is not running. Do you want to start Artifactory?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) start_artifactory; break;;
            No ) echo "You may run into unintended behaviour..." ; break;;
        esac
    done
elif [ "$(curl -su $ARTI_CREDS $ARTI_URL/api/system/ping)" != "OK" ]; then
    .log 7 "values_precheck_fn:Artifactory ping != OK"
    echo "Oh no, your key is probably incorrect. I'm getting $(echo $apikey)"
    echo "I'm going to regenerate your $PARENT_SCRIPT_DIR/json/artifactoryValues.json."
    # rm $PARENT_SCRIPT_DIR/json/artifactoryValues.json
    set_up
    echo "Completed, please run your command again."
    exit
fi

case  "$1" in
    check)
	    $PARENT_SCRIPT_DIR/common/upgradeScriptToLatest.sh;;
    upgrade)
        $SCRIPT_DIR/upgradeArtifactoryToLatest.sh;;
    restart)
        stop_artifactory;
        start_artifactory;;
    default)
        $ARTI_HOME/bin/artifactory.sh $2;;
    status)
        curl -u $ARTI_CREDS $ARTI_URL/api/system/ping;
        echo "";
        curl -u $ARTI_CREDS $ARTI_URL/api/system/version;;
    logger)
        echo "$2ing $4 logger for $3"
        TWO=$2
        . $SCRIPT_DIR/loggerAppender.sh $2 $TWO $3 $4;;
    start)
        start_artifactory;;
    stop)
        stop_artifactory;;
    tail)
        tail -F $ARTI_HOME/logs/$2.log;;
   *)
        echo $"Usage: arti (commands ... )";
        echo "commands:";
        echo "  check   = Check for latest script version and optionally upgrade";
        echo "  upgrade = Upgrade Artifactory to latest, or a specified version";
        echo "  restart = Restart Artifactory";
        echo "  start   = Start Artifactory";
        echo "  status  = Artifactory Status";
        echo "  stop    = Stop Artifactory";
        echo "  default = Normal Artifactory command script + [options]";
        echo "  tail    = Tail Artifactory logs";;
esac