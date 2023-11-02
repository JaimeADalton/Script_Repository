#!/bin/bash

RED='\e[1;31m'
YELLOW='\e[1;33m'
GREEN='\e[1;32m'
NC='\e[0m'

awk '
/CRITIC|Critic|FAIL|down/ { gsub(/CRITIC|Critic|FAIL|down/, "\033[1;31m&\033[0m") }
/WARNING|warn|NOTICE|notice|DEPRECATED|deprecated|RETRY|retry|TIMEOUT|timeout|DELAY|delay|PENDING|pending/ { gsub(/WARNING|warn|NOTICE|notice|DEPRECATED|deprecated|RETRY|retry|TIMEOUT|timeout|DELAY|delay|PENDING|pending/, "\033[1;33m&\033[0m") }
/info|INFO|DEBUG|DDEBUG|SUBDEBUG|SUCCESS|success|OK|ok|PASSED|passed|UP|Up|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|[0-9A-Fa-f]{2}[:-]{5}[0-9A-Fa-f]{2}/ { gsub(/info|INFO|DEBUG|DDEBUG|SUBDEBUG|SUCCESS|success|OK|ok|PASSED|passed|UP|Up|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|[0-9A-Fa-f]{2}[:-]{5}[0-9A-Fa-f]{2}/, "\033[1;32m&\033[0m") }
{ print }
' $1
