#!/bin/bash
#
# Purpose: Custom Xray Commands Master Script
# Requirements: jq | curl | Xray credentials
# Author: Loren Y
#

SCRIPT_DIR=`dirname $0`;
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"

if [ ! -f $PARENT_SCRIPT_DIR/json/xrayValues.json ]; then
echo "Could not find xrayValues.json, generating:"
    while true; do
        echo "Enter your Xray URL (e.g. http://localhost:8000):"
        read xray_url
        if [ "$(curl -s $xray_url/api/v1/system/ping | jq -r .status)" != "pong" ]; then
            echo "Xray doesn't look to be either running or reachable from here."
        else
            break
        fi  
    done

    echo "Enter your $xray_url username:"
    read username
    echo "Enter your $xray_url password:"
    read -s password

    while true; do
        echo "Enter your \$XRAY_HOME location (e.g. /Users/loreny/.jfrog/xray):"
        read xray_home
        if [ "$xray_home" != "/" ]; then
            xray_home=$(echo $xray_home | sed 's:/*$::')
        fi
        if [ ! -d "$xray_home" ]; then
            echo "$xray_home doesnt exist."
        else
            break
        fi  
    done
    while true; do
        echo "Enter your Xray Directory location (e.g. /Users/loreny/xray):"
        read xray_dir
        if [ "$xray_dir" != "/" ]; then
            xray_dir=$(echo $xray_dir | sed 's:/*$::')
        fi
        if [ ! -d "$xray_dir" ]; then
            echo "$xray_dir doesnt exist."
        else
            break
        fi  
    done
    echo "Select your Xray installation type:"
    select install_type in "Zip" "Docker" "Centos" "Debian" "Redhat" "Ubuntu"; do
        case $install_type in
            Zip ) echo "Currently not supported"; exit;;
            Docker ) break;;
            Centos ) echo "Currently not supported" ; exit;;
            Debian ) echo "Currently not supported"; exit;;
            Redhat ) echo "Currently not supported" ; exit;;
            Ubuntu ) echo "Currently not supported"; exit;;
        esac
    done
    echo "Creating $PARENT_SCRIPT_DIR/json/xrayValues.json"
    echo -e "{\"username\":\""$username"\", \"password\":\""$password"\", \"xray_home\":\""$xray_home"\", \"xray_url\":\""$xray_url"\", \"xray_dir\":\""$xray_dir"\",  \"install_type\":\""$install_type"\"}" > $PARENT_SCRIPT_DIR/json/xrayValues.json
fi
XRAY_HOME=$(jq -r '.xray_home' $PARENT_SCRIPT_DIR/json/xrayValues.json)
XRAY_URL=$(jq -r '.xray_url' $PARENT_SCRIPT_DIR/json/xrayValues.json)
XRAY_CREDS=$(jq -r '"\(.username):\(.password)"' $PARENT_SCRIPT_DIR/json/xrayValues.json)
XRAY_DIR=$(jq -r '.xray_dir' $PARENT_SCRIPT_DIR/json/xrayValues.json)

case  "$1" in
    check)
        $PARENT_SCRIPT_DIR/common/upgradeScriptToLatest.sh;;
    upgrade)
        $SCRIPT_DIR/upgradeXrayToLatest.sh;;
    restart)
        $XRAY_DIR/xray restart;;
    status)
        curl -u $XRAY_CREDS $XRAY_URL/api/v1/system/ping;
        echo "";;
    baseUrl)
        $SCRIPT_DIR/setBaseUrl.sh;;   
    start)
        $XRAY_DIR/xray start;;
    stop)
        $XRAY_DIR/xray stop;;
    ps)
        $XRAY_DIR/xray ps;;
    default)
        $XRAY_DIR/xray $2;;
    disableRestart)
        $SCRIPT_DIR/disableRestart.sh;;     
    *)
        echo $"Usage: xray (commands ... )";
        echo "commands:";
        echo "  check   = Check for latest script version and optionally upgrade";
        echo "  upgrade = Upgrade Xray to latest, or a specified version";
        echo "  restart = Restart Xray";
        echo "  start   = Start Xray";
        echo "  status  = Xray Status";
        echo "  stop    = Stop Xray";
        echo "  ps      = Xray microservices' status"
        echo "  baseUrl = Change Xray Base URL to current internal IP";
        echo "  disableRestart = Disable Xray Docker restart";
        echo "  default = Normal Xray command script + [options]";;
esac
