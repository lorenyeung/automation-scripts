#!/bin/bash
#
# Purpose: Custom Artifactory Commands Script master
# Requirements:  jq | Artifactory credentials
# Author: Loren Y
#

SCRIPT_VERSION=v1.0.4
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

linuxVersion() {
    echo "Finding out Linux distribution..."
    DIST=
    select install_type in "redhat" "centos" "debian" "ubuntu" "mac"; do
        case $install_type in
            redhat ) 
                grep -q -i "release 6" /etc/redhat-release >/dev/null 2>&1
                if [ $? -eq 0 ]; then DIST_VER="6"; fi

                grep -q -i "release 7" /etc/redhat-release >/dev/null 2>&1
                if [ $? -eq 0 ]; then DIST_VER="7"; fi
                DIST=redhat
                break;;
            centos ) 
                cat /etc/*-release | grep -i centos > /dev/null
                if [ $? -eq 0 ]; then DIST=centos; DIST_VER="7"; fi
                break;;
                debian )
                DIST=debian
                break;;
            ubuntu )
                DIST=ubuntu
                break;;
            mac ) 
                DIST=mac
                break;;
        esac
    done   
    echo selected $DIST $DIST_VER.
}

installPrerequisites() {
    installWget=false
    installCurl=false
    installJq=false

    type jq >/dev/null 2>&1 || { 
        echo >&2 "I require jq but it's not installed. Do you want to install it now?"; 
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) installJq=true; break;;
                No ) echo "Exiting..." ; exit;;
            esac
        done
    }

    type wget >/dev/null 2>&1 || { 
        echo >&2 "I require wget but it's not installed. Do you want to install it now?";
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) installWget=true; break;;
                No ) echo "Exiting..." ; exit;;
            esac
        done
    }

    type curl >/dev/null 2>&1 || { 
        echo >&2 "I require curl but it's not installed. Do you want to install it now?";
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) installCurl=true; break;;
                No ) echo "Exiting..." ; exit;;
            esac
        done
    }

    case ${DIST} in
        centos|redhat)
            if [ "$installWget" = true ]; then
                yum install -y wget
                type wget >/dev/null 2>&1 || { echo >&2 "Failed to install wget. Exiting..."; exit 1; }
                echo "wget installed"
            fi
            
            if [ "$installCurl" = true ]; then
                yum install -y curl
                type curl >/dev/null 2>&1 || { echo >&2 "Failed to install curl. Exiting..."; exit 1; }
                echo "curl installed"
            fi
            if [ "$installJq" = true ]; then
                ## RHEL/CentOS 7 64-Bit ##
                wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
                rpm -ivh epel-release-latest-7.noarch.rpm
                rm epel-release-latest-7.noarch.rpm
                yum install jq -y
                jq --version
            fi
            ;;
        debian)
            ;;
        ubuntu)
            ;;
        mac)
            if [ "$installWget" = true ]; then
                brew install wget
            fi
            if [ "$installJq" = true ]; then
                brew install jq
            fi
            ;;
        *)
            echo "$DIST is not supported"
            exit 1;;
    esac
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

prerequisites() {
    echo "Is your Linux distribution $DIST $DIST_VER?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) installPrerequisites; break;;
            No ) echo "Exiting..." ; exit;;
        esac
    done
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

check_script() {
    curl https://api.github.com/repos/lorenyeung/automation-scripts/releases/latest > $SCRIPT_DIR/.latest_version.txt
    LATEST_SCRIPT_VERSION=$(jq -r '.tag_name' $SCRIPT_DIR/.latest_version.txt)
    LATEST_SCRIPT_TAG=$(jq -r '.name' $SCRIPT_DIR/.latest_version.txt)
    if [ "$SCRIPT_VERSION" = "$LATEST_SCRIPT_VERSION" ]; then
        echo "You are on the latest version, which is $SCRIPT_VERSION."
    else
        echo "You are on $SCRIPT_VERSION, the latest script version is $LATEST_SCRIPT_VERSION. Would you like to upgrade?"
        select yn in "Yes" "No"; do
            case $yn in
                Yes ) 
                    echo "Downloading $LATEST_SCRIPT_VERSION";
                    LATEST_SCRIPT_DL=$(jq -r '.tarball_url' $SCRIPT_DIR/.latest_version.txt)
                    curl -L https://github.com/lorenyeung/automation-scripts/archive/$LATEST_SCRIPT_VERSION.tar.gz -o "$SCRIPT_DIR/download-$LATEST_SCRIPT_VERSION.tar.gz"
                    echo "Extracting"

                    echo $PARENT_SCRIPT_DIR $PARENT2_SCRIPT_DIR 
                    tar -xf $SCRIPT_DIR/download-$LATEST_SCRIPT_VERSION.tar.gz -C $PARENT2_SCRIPT_DIR/
                    echo "Updating metadata from $SCRIPT_VERSION to $LATEST_SCRIPT_VERSION"
                    echo -e "{\"script_version\":\"$SCRIPT_VERSION\"}" > $PARENT_SCRIPT_DIR/json/metadata.json
                    cp -r $PARENT_SCRIPT_DIR/json $PARENT2_SCRIPT_DIR/automation-scripts-$LATEST_SCRIPT_TAG/json
                    echo "Last step: rm -r $PARENT_SCRIPT_DIR && mv $PARENT2_SCRIPT_DIR/automation-scripts-$LATEST_SCRIPT_TAG $PARENT_SCRIPT_DIR, and open a new shell :)"
                    break;;
                No ) echo "welp" ; break;;
            esac
        done
    fi
    #rm $SCRIPT_DIR/.latest_version.txt     
}

if [ ! -f $PARENT_SCRIPT_DIR/json/metadata.json ]; then
    echo "Welcome to Loren's automation scripts. Looks like its your first time running this set of scripts. You're on version $SCRIPT_VERSION. Creating $PARENT_SCRIPT_DIR/json/metadata.json..."
    if [ ! -d $PARENT_SCRIPT_DIR/json ]; then
        mkdir $PARENT_SCRIPT_DIR/json
    fi
    echo -e "{\"script_version\":\"$SCRIPT_VERSION\"}" > $PARENT_SCRIPT_DIR/json/metadata.json
    # curl https://api.github.com/repos/lorenyeung/automation-scripts/releases/tags/v1.0.0
fi

if [ ! -f $PARENT_SCRIPT_DIR/json/artifactoryValues.json ]; then
    echo "Welcome to the Custom Artifactory commands master script. Please ensure that anonymous access is enabled."    
    linuxVersion
    prerequisites
    echo "I could not find $DIR/artifactoryValues.json, generating:"
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
	    check_script;;
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
