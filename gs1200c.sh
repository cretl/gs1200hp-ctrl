#!/bin/bash

# Copyright (C) 2023 Pavel Löbl
#
# Based on https://github.com/cretl/gs1200hp-ctrl/
#
# gs1200hp-ctrl-ng is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# gs1200hp-ctrl-ng is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with gs1200hp-ctrl-ng.  If not, see <http://www.gnu.org/licenses/>.

# user settings
SWITCH_IP="zyxel-poe"
PASSWORD="12341234"

# global variables
passwordNeedsEncryption=""
cookieJarFile=""

showHelp() {
  echo "usage: $0 {on|off|toggle|status} {1|2|3|4|all}"
  exit
}

die() {
  echo "$@"
  switchLogout
  rm $cookieJarFile >/dev/null 2>&1
  exit 2
}

checkCompatibility() {
  compatibleSwitchModel="GS1200-5HP v2"
  compatibleSwitchFirmwareVersion=("V2.00(ABKN.1)C0" "V2.00(ABKN.2)C0")

  switchInfo=$(curl -s http://${SWITCH_IP}/system_data.js --fail)
  [ -z "${switchInfo}" ] && die "compatibility check failed: cannot get switch data"

  switchModel=$(echo -n "$switchInfo" | grep model_name | cut -d "'" -f2)
  [ -z "${switchModel}" ] && die "compatibility check failed: cannot get switch model"
  [ "${switchModel}" != "${compatibleSwitchModel}" ] && die "compatibility check failed: ${switchModel} is not compatible"

  switchFirmwareVersion=$(echo -n "$switchInfo" | grep sys_fmw_ver | cut -d "'" -f2)
  [ -z "${switchFirmwareVersion}" ] && "compatibility check failed: couldn't get switch firmware version"

  for ver in "${compatibleSwitchFirmwareVersion[@]}"; do
    [ "$switchFirmwareVersion" == "$ver" ] && passwordNeedsEncryption="1"
  done
}

convertCodeToChar() {
  printf "\\$(printf '%03o' "$1")"
}

convertCharToCode() {
  LC_CTYPE=C printf '%d' "'$1"
}

encryptAdminPw() {
  declare -a adminPwArray #array to split password characters into
  declare -a adminEncPwArray #array with adapted ("encrypted") password characters codes
  declare -a adminEncPwArrayWithRandomChars #final array with random characters added before every character

  for ((i=0; i<${#PASSWORD}; i++))
  do
    adminPwArray[$i]="${PASSWORD:$i:1}"
    charCode=$(convertCharToCode ${adminPwArray[$i]})
    newCharCode="$(( ${charCode} - ${#PASSWORD} ))"
    newChar=$(convertCodeToChar $newCharCode)

    adminEncPwArray[$i]="$newChar"

    adminEncPwArrayWithRandomChars+="a"
    adminEncPwArrayWithRandomChars+="$newChar"
  done

  adminEncPwArrayWithRandomChars+="a"
  PASSWORD="$(printf %s "${adminEncPwArrayWithRandomChars[@]}" $'\n')"
}

switchLogin() {
  rm $cookieJarFile >/dev/null 2>&1
  [ -n "$passwordNeedsEncryption" ] && encryptAdminPw
  responseLogin=$(curl -c ${cookieJarFile} -s "http://${SWITCH_IP}/login.cgi" -X POST --data-urlencode "password=${PASSWORD}" -H "Content-Type: application/x-www-form-urlencoded" -H "Connection: keep-alive" -H "Origin: http://${SWITCH_IP}" -H "Referer: http://${SWITCH_IP}/" -w "%{http_code}" --fail -o /dev/null)

  [ "${responseLogin}" -ne "200" ] && die "cannot login"
}

switchLogout() {
  responseLogout=$(curl -b ${cookieJarFile} -c ${cookieJarFile} -s "http://${SWITCH_IP}/logout.html" -w "%{http_code}" --fail -o /dev/null)

  [ "${responseLogout}" -ne "200" ] && die "logout failed"
  rm $cookieJarFile >/dev/null 2>&1
}

getPOEState() {
  currActivePoePortsBit=$(curl -b ${cookieJarFile} -s "http://${SWITCH_IP}/port_state_data.js" -H 'Connection: keep-alive' | grep portPoE | grep 'var  *portPoE  *=')

  [ $? -ne 0 ] && die "failed to get port state"

  echo $currActivePoePortsBit | cut -d"'" -f 2
}

setPoePortBit() {
  newMask=$1
  responseSetPoePortBit=$(curl -b ${cookieJarFile} -s "http://${SWITCH_IP}/port_state_set.cgi" --data "g_port_state=31&g_port_flwcl=0&g_port_poe=${newMask}&g_port_speed0=0&g_port_speed1=0&g_port_speed2=0&g_port_speed3=0&g_port_speed4=0" -w "%{http_code}" --fail -o /dev/null)

  [ "${responseSetPoePortBit}" -ne "200" ] && die "failed to set port state"
}

switchPort() {
  port=$1
  action=$2
  bitfield=$3
  port=$((port - 1))
  case $action in
    on)
      bitfield=$((bitfield | 1 << port))
      ;;
    off)
      bitfield=$((bitfield & (bitfield - (1 << port))))
      ;;
    toggle)
      bitfield=$((bitfield ^ (1 << port)))
      ;;
  esac
  echo $bitfield
}

changePortState() {
  state=$1
  port=$2
  poeMask=`getPOEState`
  case $port in
    1|2|3|4)
      poeMask=`switchPort $port $state $poeMask`
      ;;
    all)
      for p in 1 2 3 4; do
	poeMask=`switchPort $p $state $poeMask`
      done
      ;;
  esac
  setPoePortBit $poeMask
}

printStatus() {

  poeMask=`getPOEState`

  echo "Port  |  1|  2|  3|  4|"
  echo "------|---|---|---|---|"
  echo -n "State |"

  for port in 0 1 2 3; do
    if [ $((poeMask & (1 << port))) -ne 0 ];then
      echo -n " on|"
    else
      echo -n "off|"
    fi
  done
  echo
}

cookieJarFile=`mktemp`

checkCompatibility

case $1 in
  on|off|toggle)
    [ $# -ne 2 ] && showHelp
    case $2 in
      1|2|3|4|all)
	switchLogin
    	changePortState $1 $2
    	switchLogout
	;;
      *)
	showHelp
	;;
    esac
    ;;
  status)
    [ $# -ne 1 ] && showHelp
    switchLogin
    printStatus
    switchLogout
    ;;
esac

exit 0
