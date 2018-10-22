#!/bin/bash
#
# Purpose: installing tools - this script is only called from others.
# Requirements: basic PMs of each linux distro
# Author: Loren Y
#

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

prerequisites() {
    echo "Is your Linux distribution $DIST $DIST_VER?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) installPrerequisites; break;;
            No ) echo "Exiting..." ; exit;;
        esac
    done
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

linuxVersion
prerequisites