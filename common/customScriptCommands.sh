#!/bin/bash
#
# Purpose: Custom Script Commands Master Script
# Requirements: jq | curl | Xray credentials
# Author: Loren Y
#

SCRIPT_DIR=`dirname $0`;
PARENT_SCRIPT_DIR="$(dirname "$SCRIPT_DIR")"
PARENT2_SCRIPT_DIR="$(dirname "$PARENT_SCRIPT_DIR")"

case  "$1" in
    check)
        $PARENT_SCRIPT_DIR/common/upgradeScriptToLatest.sh;;
    preqs)
        $PARENT_SCRIPT_DIR/common/installPrerequisites.sh;;
    auto)
        $PARENT_SCRIPT_DIR/common/upgradeServices.sh;;  
    *)
        echo $"Usage: loren (commands ... )";
        echo "commands:";
        echo "  check   = Check for latest script version and optionally upgrade";
        echo "  preqs   = install pre-requisities";
        echo "  auto    = Set up automatic upgrade of services";
esac