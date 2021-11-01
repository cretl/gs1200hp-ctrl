#!/bin/bash

## ----------------------------
## INFO
## -----
# script version: 0.12
# script version date: 2021/11/01
# dependencies: Bash, curl, printf
#
# Zyxel GS1200-5HPv2
# firmware version: V2.00(ABKN.1)C0
# ports 1-4 = PoE; port 5 = non-PoE
# switch layout (front view):
# [ p1 ] - [ p2 ] - [ p3 ] - [ p4 ] - [ p5 ]
# values: port1=2^0;	port2=2^1;	port3=2^2;	port4=2^3
# values: port1=1;	port2=2;	port3=4;	port4=8
# combos examples: 0=[off]; 1=[1 on]; 3=[1&2 on]; 5=[1&2&3 on]; 15=[1&2&3&4 on];
#
## ----------------------------

## ----------------------------
## SETTINGS
## --------
switchIP="192.168.0.2"
adminPw="12345678DEF"
cookieJarFile="/tmp/gs1200cookies"
## ----------------------------


## NO MODIFICATIONS NEEDED AFTER THIS LINE

par1=$1
par2=$2

declare -a indexPoePort=(0 1 2 4 8)
declare -a isActivePoePort=(0 0 0 0 0)

wantedPort=""
wantedPortNumber=""
wantedPortValue=""
wantedAction=""
wantedOperator=""
calculatedPoePortBit=""

showHelp() {
  echo "Usage: $0 {on|off|status} {1|2|3|4|all}"
}

selectedAction() {
  case "${par1}" in
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
  case "${par2}" in
    1)
      wantedPortNumber=${par2};
      wantedPortValue=${indexPoePort[${par2}]};
    ;;
    2)
      wantedPortNumber=${par2};
      wantedPortValue=${indexPoePort[${par2}]};
    ;;
    3)
      wantedPortNumber=${par2};
      wantedPortValue=${indexPoePort[${par2}]};
    ;;
    4)
      wantedPortNumber=${par2};
      wantedPortValue=${indexPoePort[${par2}]};
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

checkCompatibility() {
  compatibleSwitchModel="GS1200-5HP v2"
  compatibleSwitchFirmwareVersion="V2.00(ABKN.1)C0"

  switchInfo=$(curl -s http://${switchIP}/system_data.js --fail)
  if [ -z "${switchInfo}" ]; then echo "Compatibility check failed. The script may not work."; return 1; fi

  switchModel=$(echo -n "$switchInfo" | grep model_name | cut -d "'" -f2)
  if [ -z "${switchModel}" ]; then echo "Compatibility check failed ... Couldn't get switch model."; return 1; fi
  if [ "${switchModel}" != "${compatibleSwitchModel}" ]; then echo "Compatibility check failed ... ${switchModel} is not compatible."; return 1; fi

  switchFirmwareVersion=$(echo -n "$switchInfo" | grep sys_fmw_ver | cut -d "'" -f2)
  if [ -z "${switchFirmwareVersion}" ]; then echo "Compatibility check failed ... Couldn't get switch firmware version."; return 1; fi

  return 0
}

convertCodeToChar() {
  #convertCodeToChar <code>
  printf "\\$(printf '%03o' "$1")"
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
  declare -a adminPwArray #array to split password characters into
  declare -a adminEncPwArray #array with adapted ("encrypted") password characters codes
  declare -a adminEncPwArrayWithRandomChars #final array with random characters added before every character

  for ((i=0; i<${#adminPw}; i++))
  do
    adminPwArray[$i]="${adminPw:$i:1}"
    charCode=$(convertCharToCode ${adminPwArray[$i]})
    newCharCode="$(( ${charCode} - ${#adminPw} ))"
    newChar=$(convertCodeToChar $newCharCode)

    adminEncPwArray[$i]="$newChar"

    adminEncPwArrayWithRandomChars+="$(generateRandomChar)"
    adminEncPwArrayWithRandomChars+="$newChar"
  done
  
  adminEncPwArrayWithRandomChars+="$(generateRandomChar)"
  adminPw="$(printf %s "${adminEncPwArrayWithRandomChars[@]}" $'\n')"
}

login() {
  rm ${cookieJarFile} >/dev/null 2>&1
  responseLogin=$(curl -c ${cookieJarFile} -s "http://${switchIP}/login.cgi" -X POST --data-raw "password=${adminPw}" -H "Content-Type: application/x-www-form-urlencoded" -H "Connection: keep-alive" -H "Origin: http://${switchIP}" -H "Referer: http://${switchIP}/" -w "%{http_code}" --fail -o /dev/null)

  if [ "${responseLogin}" -ne "200" ] ; then

    echo "Login failed. Status Code != 200. Exiting ..."
    exit 1

  elif [ "${responseLogin}" -eq "200" ] ; then
  
  cookieJarToken=$(cat ${cookieJarFile} | grep token | awk '{print $7}')

    if [[ "$cookieJarToken" =~ ^[a-zA-Z0-9]{16}$ ]]; then
      echo "Login successful."
    else
      echo "Login failed. Token not found in Cookie Jar. Exiting ... "
      exit 1
    fi
    
  fi
}

logout() {
  responseLogout=$(curl -b ${cookieJarFile} -c ${cookieJarFile} -s "http://${switchIP}/logout.html" -w "%{http_code}" --fail -o /dev/null)

  if [ "${responseLogout}" -ne "200" ] ; then
    echo "Logout failed. Exiting ..."
    rm ${cookieJarFile} >/dev/null 2>&1
    exit 1
  elif [ "${responseLogout}" -eq "200" ] ; then

    cookieJarToken=$(cat ${cookieJarFile} | grep token | awk '{print $7}')

    if [[ "$cookieJarToken" =~ ^[a-zA-Z0-9]{16}$ ]]; then
      echo "Logout failed. Token still found in Cookie Jar. Exiting ... "
      rm ${cookieJarFile} >/dev/null 2>&1
      exit 1
    else
      echo "Logout successful. Exiting ... "
      rm ${cookieJarFile} >/dev/null 2>&1
    fi

  fi
}

analyzeActivePoePort() {
  currActivePoePortsBit=$(curl -b ${cookieJarFile} -s "http://${switchIP}/port_state_data.js" -H 'Connection: keep-alive' | grep portPoE | cut -d"'" -f 2)

  case $currActivePoePortsBit in
    0)
      isActivePoePort[1]="off"
      isActivePoePort[2]="off"
      isActivePoePort[3]="off"
      isActivePoePort[4]="off"
      ;;
    1)
      isActivePoePort[1]="on"
      isActivePoePort[2]="off"
      isActivePoePort[3]="off"
      isActivePoePort[4]="off"
      ;;
    2)
      isActivePoePort[1]="off"
      isActivePoePort[2]="on"
      isActivePoePort[3]="off"
      isActivePoePort[4]="off"
      ;;
    4)
      isActivePoePort[1]="off"
      isActivePoePort[2]="off"
      isActivePoePort[3]="on"
      isActivePoePort[4]="off"
      ;;
    8)
      isActivePoePort[1]="off"
      isActivePoePort[2]="off"
      isActivePoePort[3]="off"
      isActivePoePort[4]="on"

      ;;
    3)
      isActivePoePort[1]="on"
      isActivePoePort[2]="on"
      isActivePoePort[3]="off"
      isActivePoePort[4]="off"
      ;;
    5)
      isActivePoePort[1]="on"
      isActivePoePort[2]="off"
      isActivePoePort[3]="on"
      isActivePoePort[4]="off"
      ;;
    9)
      isActivePoePort[1]="on"
      isActivePoePort[2]="off"
      isActivePoePort[3]="off"
      isActivePoePort[4]="on"
      ;;
    6)
      isActivePoePort[1]="off"
      isActivePoePort[2]="on"
      isActivePoePort[3]="on"
      isActivePoePort[4]="off"
      ;;
    10)
      isActivePoePort[1]="off"
      isActivePoePort[2]="on"
      isActivePoePort[3]="off"
      isActivePoePort[4]="on"
      ;;
    12)
      isActivePoePort[1]="off"
      isActivePoePort[2]="off"
      isActivePoePort[3]="on"
      isActivePoePort[4]="on"
      ;;
    7)
      isActivePoePort[1]="on"
      isActivePoePort[2]="on"
      isActivePoePort[3]="on"
      isActivePoePort[4]="off"
      ;;
    11)
      isActivePoePort[1]="on"
      isActivePoePort[2]="on"
      isActivePoePort[3]="off"
      isActivePoePort[4]="on"
      ;;
    13)
      isActivePoePort[1]="on"
      isActivePoePort[2]="off"
      isActivePoePort[3]="on"
      isActivePoePort[4]="on"
      ;;
    14)
      isActivePoePort[1]="off"
      isActivePoePort[2]="on"
      isActivePoePort[3]="on"
      isActivePoePort[4]="on"
      ;;
    15)
      isActivePoePort[1]="on"
      isActivePoePort[2]="on"
      isActivePoePort[3]="on"
      isActivePoePort[4]="on"
      ;;
    *)
      echo "Failed to get currActivePoePortsBit. Exiting ..."
      logout
      exit 1
    ;;
  esac
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

  if [ ${wantedPortNumber} = 0 ]; then
  #all ports selected

    allPortsEqualWantedAction=true
    i=1
    while [ ${i} -lt ${#isActivePoePort[@]} ]
    do
      if [ "${isActivePoePort[${i}]}" != "${wantedAction}" ]; then
        allPortsEqualWantedAction=false
        break
      fi
      i=$(( ${i} + 1 ))
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

    if [ ${calculatedPoePortBit} -eq ${currActivePoePortsBit} ]; then

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
       
       calculatedPoePortBit=$((${currActivePoePortsBit} + ${wantedPortValue}))
       
    elif [ "${wantedAction}" = "off" ]; then

       if [ "${isActivePoePort[${wantedPortNumber}]}" = "off" ]; then
         echo "Port${wantedPortNumber} is already switched ${wantedAction}. Exiting ..."
         logout
         exit 1
       fi

       calculatedPoePortBit=$((${currActivePoePortsBit} - ${wantedPortValue}))

    fi

    if [ ${calculatedPoePortBit} -eq ${currActivePoePortsBit} ]; then

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

  echo "Setting PoePortBit ..."
  setPoePortBit
  echo "action done."
  echo "  "
  echo "Status after action:"
  getStatus
}

getStatus() {
  analyzeActivePoePort

  echo "  "
  echo "Port : Status"
  echo "-----:-------"

  if [ ${wantedPortNumber} = 0 ]; then

    i=1
    while [ ${i} -lt ${#isActivePoePort[@]} ]
    do
      status=${isActivePoePort[${i}]^^}
      echo "P${i}   : ${status}"
      i=$(( ${i} + 1 ))
    done

  else
    
    status=${isActivePoePort[${wantedPortNumber}]^^}
    echo "P${wantedPortNumber}   : ${status}"

  fi

  echo "-----:-------"
  echo "  "
}

selectedAction
selectedPort

checkCompatibility

if [ "$switchFirmwareVersion" == "$compatibleSwitchFirmwareVersion" ]; then encryptAdminPw; fi

login

if [ "${wantedAction}" = "on" ] || [ "${wantedAction}" = "off" ]; then
  switchOnOff
elif [ "${wantedAction}" = "status" ]; then
  getStatus
fi

logout

exit 0
