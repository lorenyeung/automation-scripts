#!/bin/bash
#
# Purpose: installing tools - this script is only called from others.
# Requirements: basic PMs of each linux distro
# Author: Loren Y
#
SCRIPT_DIR=`dirname $0`;
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"

installPrerequisites() {
    declare -a NEED_DEP=("wget" "curl" "jq")
    declare -a INSTALL_DEP
    for i in "${NEED_DEP[@]}"; do
        type $i >/dev/null 2>&1 || {
            echo >&2 "I require $i but it's not installed. Do you want to install it now?"; 
            select yn in "Yes" "No"; do
                case $yn in
                    Yes ) 
                        INSTALL_DEP+=("$i"); break;;
                    No ) echo "Exiting..."; exit;;
                esac
            done
        }
    done
    echo "installing ${INSTALL_DEP[@]}..."

    case ${DIST} in
        centos|redhat)
            for j in "${INSTALL_DEP[@]}"; do
		        yum install $j -y
		        type $j >/dev/null 2>&1 || { echo >&2 "Failed to install $j."; }
            done
            ## RHEL/CentOS 7 64-Bit ##
            wget http://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            rpm -ivh epel-release-latest-7.noarch.rpm
            rm epel-release-latest-7.noarch.rpm
            yum install jq -y
            ;;
        debian)
        # not tested
            for j in "${INSTALL_DEP[@]}"; do
		        apt-get install $j -y
		        type $j >/dev/null 2>&1 || { echo >&2 "Failed to install $j."; }
            done	
            ;;
        ubuntu)
            for j in "${INSTALL_DEP[@]}"; do
		        apt-get install $j -y
		        type $j >/dev/null 2>&1 || { echo >&2 "Failed to install $j."; }
            done	
            ;;
        mac)
            for j in "${INSTALL_DEP[@]}"; do
		        brew install $j -y
		        type $j >/dev/null 2>&1 || { echo >&2 "Failed to install $j."; }
            done
            ;;
        *)
            echo "$DIST is not supported"
            exit 1;;
    esac
    echo "Final preflight check:"
    for j in "${INSTALL_DEP[@]}"; do
        type $j >/dev/null 2>&1 || { echo >&2 "I Failed to install $j. Exiting.."; exit 1 }
    done
    file=$(jq -r '.installed_deps=true' $PARENT_SCRIPT_DIR/metadata.json)
    echo $file > $PARENT_SCRIPT_DIR/metadata.json
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

linuxDistro() {
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
    file=$(jq -r '.linux_distro="'$DIST'"' $PARENT_SCRIPT_DIR/metadata.json)
    echo $file > $PARENT_SCRIPT_DIR/metadata.json
}

LINUX_DISTRO=$(jq -r '.linux_distro' $PARENT_SCRIPT_DIR/metadata.json)
if [ -z $LINUX_DISTRO ]; then
    linuxDistro
fi
prerequisites