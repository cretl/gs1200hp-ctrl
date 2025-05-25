#!/bin/bash

## ----------------------------
## INFO
## -----
# script version: 0.15
# script version date: 2024/08/24
# dependencies: Bash, curl, printf, logger
#
# Zyxel GS1200-5HPv2
# firmware version: V2.00(ABKN.3)C0
# ports 1-4 = PoE; port 5 = non-PoE
# switch layout (front view):
# [ p1 ] - [ p2 ] - [ p3 ] - [ p4 ] - [ p5 ]
# values: port1=2^0;	port2=2^1;	port3=2^2;	port4=2^3
# values: port1=1;	port2=2;	port3=4;	port4=8
# combos examples: 0=[off]; 1=[1 on]; 3=[1&2 on]; 7=[1&2&3 on]; 15=[1&2&3&4 on];
#
## ----------------------------

## ----------------------------
## SETTINGS
## --------
switchIP="192.168.0.2"
adminPw="12345678DEF"
cookieJarFile="/tmp/gs1200cookies"

#Debug Mode Settings
debugMode=false #display debug messages
debugMessageSyslogMode=false #log debug messages to syslog
## ----------------------------


## NO MODIFICATIONS NEEDED AFTER THIS LINE

## ----------------------------
## STATIC VARIABLES
## --------

declare -a indexPoePort=(0 1 2 4 8)
declare -a isActivePoePort=(0 0 0 0 0)

wantedPortNumber=""
wantedPortValue=""
wantedAction=""
calculatedPoePortBit=""

wantedOperator="$1"
wantedPort="$2"

## ----------------------------
## FUNCTIONS
## --------

checkDependencies() {
  declare -a scriptDependencies=("bash" "curl" "printf" "logger")

  for dependency in "${scriptDependencies[@]}"; do
    if [[ ! $(command -v "${dependency}") ]]; then
      echo "Depedency ${dependency} not found! The script won't work."
      echo "Please check/install the dependencies: ${scriptDependencies[*]}."
      echo "Exiting ..."
      exit 1
    fi
  done
}

debugMessage() {
#debugMessage ${debugMessageContent}
  if [ "${debugMode}" = true ]; then
    echo "#${1}"
  fi
  if [ "${debugMessageSyslogMode}" = true ]; then
    syslogMessage "${1}"
  fi
}

exitOnError() {
  syslogMessage "$1"
  echo "ERROR:"
  echo "$1"
  echo "Exiting ..."
  doCleanup
  exit 1
}

syslogMessage() {
  #syslogMessage $message
  #logger required!
  logger -t "$0" "$1"
}

showHelp() {
  echo "Usage: $0 {on|off|status} {1|2|3|4|all}"
}

doCleanup() {
  rm "${cookieJarFile}" >/dev/null 2>&1
}


selectedAction() {
  case "${wantedOperator}" in
    on)
      wantedAction="on"
    ;;
    off)
      wantedAction="off"
    ;;
    status)
      wantedAction="status"
    ;;
    *)
      showHelp
      exit 1
    ;;
  esac
}

selectedPort() {
  case "${wantedPort}" in
    1)
      wantedPortNumber="${wantedPort}";
      wantedPortValue="${indexPoePort[${wantedPort}]}";
    ;;
    2)
      wantedPortNumber="${wantedPort}";
      wantedPortValue="${indexPoePort[${wantedPort}]}";
    ;;
    3)
      wantedPortNumber="${wantedPort}";
      wantedPortValue="${indexPoePort[${wantedPort}]}";
    ;;
    4)
      wantedPortNumber="${wantedPort}";
      wantedPortValue="${indexPoePort[${wantedPort}]}";
    ;;
    all)
      wantedPortNumber=0;
      wantedPortValue=15;
    ;;
    *)
      showHelp
      exit 1
    ;;
  esac
}

convertCodeToChar() {
  #convertCodeToChar <code>
  oct=$(printf '%03o' "$1")
  printf '%b' "\0$oct"
}

convertCharToCode() {
  #convertCharToCode <char>
  LC_CTYPE=C printf '%d' "'$1"
}

generateRandomChar() {
  #generateRandomChar -> return one random character (space: A-Z a-z 0-9)
  tr -dc A-Za-z0-9 < /dev/urandom | head -c 1
}

encryptAdminPw() {
  declare -a adminPwArray #array to split password into characters
  declare -a adminEncPwArrayWithRandomChars #final array with random characters added before every character

  #loop through $adminPw characters and create an "encrypted" password
  for ((i=0; i<${#adminPw}; i++))
  do
    adminPwArray[i]="${adminPw:$i:1}"
    charCode=$(convertCharToCode "${adminPwArray[$i]}")
    newCharCode="$(( charCode - ${#adminPw} ))"
    newChar=$(convertCodeToChar "$newCharCode")

    adminEncPwArrayWithRandomChars+=("$(generateRandomChar)")
    adminEncPwArrayWithRandomChars+=("$newChar")
  done
  
  adminEncPwArrayWithRandomChars+=("$(generateRandomChar)")
  adminPw="$(printf %s "${adminEncPwArrayWithRandomChars[@]}" $'\n')"
}

login() {
  rm "${cookieJarFile}" >/dev/null 2>&1
  responseLogin=$(curl -c ${cookieJarFile} -s "http://${switchIP}/login.cgi" -X POST --data-raw "password=${adminPw}" -H "Content-Type: application/x-www-form-urlencoded" -H "Connection: keep-alive" -H "Origin: http://${switchIP}" -H "Referer: http://${switchIP}/" -w "%{http_code}" --fail -o /dev/null)
  
  if [ "${responseLogin}" -ne "200" ] ; then

    exitOnError "Login failed. Status Code != 200. Exiting ..."

  elif [ "${responseLogin}" -eq "200" ] ; then
  
  cookieJarToken=$(< "${cookieJarFile}" grep token | awk '{print $7}')

    if [[ "$cookieJarToken" =~ ^[a-zA-Z0-9]{16}$ ]]; then
      debugMessage "Login successful."
    else
      exitOnError "Login failed. Token not found in cookie jar. Exiting ... "
    fi
    
  fi
}

logout() {
  responseLogout=$(curl -b ${cookieJarFile} -c ${cookieJarFile} -s "http://${switchIP}/logout.html" -w "%{http_code}" --fail -o /dev/null)

  if [ "${responseLogout}" -ne "200" ] ; then

    exitOnError "Logout failed. Exiting ..."

  elif [ "${responseLogout}" -eq "200" ] ; then

    cookieJarToken=$(< "${cookieJarFile}" grep token | awk '{print $7}')

    if [[ "$cookieJarToken" =~ ^[a-zA-Z0-9]{16}$ ]]; then
      exitOnError "Logout failed. Token still found in Cookie Jar. Exiting ... "
    else
      debugMessage "Logout successful. Exiting ... "
      doCleanup
    fi

  fi
}

analyzeActivePoePort() {
  currentActivePoePortsBit=$(curl -b ${cookieJarFile} -s "http://${switchIP}/port_state_data.js" -H 'Connection: keep-alive' | grep portPoE | cut -d"'" -f 2)
  debugMessage "currentActivePoePortsBit=$currentActivePoePortsBit"
  
  debugMessage "check if currentActivePoePortsBit is an number"
  #check if currentActivePoePortsBit is an number
  if ! [[ "$currentActivePoePortsBit" =~ ^[0-9]+$ ]]; then
    echo "Error: currentActivePoePortsBit is not a number (currentActivePoePortsBit=${currentActivePoePortsBit}). Exiting ..."
    exit 1
  fi

  debugMessage "check if currentActivePoePortsBit is in correct range"
  #check if currentActivePoePortsBit is in correct range
  if ((currentActivePoePortsBit < 1 || currentActivePoePortsBit > 15)); then
    echo "Error: currentActivePoePortsBit is out of range (currentActivePoePortsBit=${currentActivePoePortsBit}). Exiting ..."
    exit 1
  fi

  #loop through all ports and check which port is on and which is off
  for ((q=1; q<${#indexPoePort[@]}; q++))
  do
    if ((currentActivePoePortsBit & indexPoePort[q])); then
      debugMessage "Port $q is on"
      isActivePoePort[q]="on"
    else
      debugMessage "Port $q is off"
      isActivePoePort[q]="off"
    fi
  done
}

setPoePortBit() {
  responseSetPoePortBit=$(curl -b ${cookieJarFile} -s "http://$switchIP/port_state_set.cgi" --data "g_port_state=31&g_port_flwcl=0&g_port_poe=${calculatedPoePortBit}&g_port_speed0=0&g_port_speed1=0&g_port_speed2=0&g_port_speed3=0&g_port_speed4=0" -w "%{http_code}" --fail -o /dev/null)

  if [ "${responseSetPoePortBit}" -ne "200" ] ; then
    echo "setPoePortBit failed. Exiting ..."
    logout
    exit 1
  elif [ "${responseSetPoePortBit}" -eq "200" ] ; then
    echo "setPoePortBit successful."
  fi
}

switchOnOff() {
  analyzeActivePoePort

  echo "Current status:"
  getStatus

  if [ "${wantedPortNumber}" = 0 ]; then
  #all ports selected

    allPortsEqualWantedAction=true
    i=1
    while [ ${i} -lt ${#isActivePoePort[@]} ]
    do
      if [ "${isActivePoePort[${i}]}" != "${wantedAction}" ]; then
        allPortsEqualWantedAction=false
        break
      fi
      i=$(( i + 1 ))
    done

    if [ "${allPortsEqualWantedAction}" = true ]; then
         echo "All PoE ports are already switched ${wantedAction}. Exiting ..."
         logout
         exit 1
    fi

    if [ "${wantedAction}" = "on" ]; then
       calculatedPoePortBit=15

    elif [ "${wantedAction}" = "off" ]; then
       calculatedPoePortBit=0
    fi

    if [ "${calculatedPoePortBit}" -eq "${currentActivePoePortsBit}" ]; then

       echo "All PoE ports are already ${wantedAction}. Exiting ..."
       logout
       exit 1
  
    fi

  echo "Switching ALL PoE ports ${wantedAction} ..."

  else
  #single port selected
  
    if [ "${wantedAction}" = "on" ]; then
       
       if [ "${isActivePoePort[${wantedPortNumber}]}" = "on" ]; then
         echo "Port${wantedPortNumber} is already switched ${wantedAction}. Exiting ..."
         logout
         exit 1
       fi
       
       calculatedPoePortBit=$((currentActivePoePortsBit + wantedPortValue))
       
    elif [ "${wantedAction}" = "off" ]; then

       if [ "${isActivePoePort[${wantedPortNumber}]}" = "off" ]; then
         echo "Port${wantedPortNumber} is already switched ${wantedAction}. Exiting ..."
         logout
         exit 1
       fi

       calculatedPoePortBit=$((currentActivePoePortsBit - wantedPortValue))

    fi

    if [ "${calculatedPoePortBit}" -eq "${currentActivePoePortsBit}" ]; then

       echo "Port${wantedPortNumber} is already ${wantedAction}. Exiting ..."
       logout
       exit 1
  
    elif [ ${calculatedPoePortBit} -gt 15 ]; then

       echo "Already active. Exiting ..."
       logout
       exit 1
  
    elif [ ${calculatedPoePortBit} -lt 0 ]; then

       echo "Already deactivated. Exiting ..."
       logout
       exit 1

    fi

  fi

  echo "Switching port${wantedPortNumber} ${wantedAction} ..."

  debugMessage "Setting PoePortBit ..."
  setPoePortBit
  debugMessage "action done."
  debugMessage "  "
  debugMessage "Status after action:"
  getStatus
}

getStatus() {
  analyzeActivePoePort

  echo "  "
  echo "Port : Status"
  echo "-----:-------"

  if [ "${wantedPortNumber}" = 0 ]; then

    i=1
    while [ ${i} -lt ${#isActivePoePort[@]} ]
    do
      status=${isActivePoePort[${i}]^^}
      echo "P${i}   : ${status}"
      i=$(( i + 1 ))
    done

  else
    
    status=${isActivePoePort[${wantedPortNumber}]^^}
    echo "P${wantedPortNumber}   : ${status}"

  fi

  echo "-----:-------"
  echo "  "
}

## ----------------------------
## SCRIPT
## --------

checkDependencies

selectedAction
selectedPort

encryptAdminPw

login

if [ "${wantedAction}" = "on" ] || [ "${wantedAction}" = "off" ]; then
  switchOnOff
elif [ "${wantedAction}" = "status" ]; then
  getStatus
fi

logout

exit 0
