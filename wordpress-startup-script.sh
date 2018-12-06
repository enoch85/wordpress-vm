#!/bin/bash
# shellcheck disable=2034,2059
true
# shellcheck source=lib.sh
WPDB=1 && MYCNFPW=1 && FIRST_IFACE=1 && CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
unset FIRST_IFACE
unset CHECK_CURRENT_REPO
unset MYCNFPW
unset WPDB

# T&M Hansson IT AB © - 2018, https://www.hanssonit.se/

## If you want debug mode, please activate it further down in the code at line ~132

# FUNCTIONS #

msg_box() {
local PROMPT="$1"
    whiptail --msgbox "${PROMPT}" "$WT_HEIGHT" "$WT_WIDTH"
}

is_root() {
    if [[ "$EUID" -ne 0 ]]
    then
        return 1
    else
        return 0
    fi
}

root_check() {
if ! is_root
then
msg_box "Sorry, you are not root. You now have two options:
1. With SUDO directly:
   a) :~$ sudo bash $SCRIPTS/name-of-script.sh
2. Become ROOT and then type your command:
   a) :~$ sudo -i
   b) :~# $SCRIPTS/name-of-script.sh
In both cases above you can leave out $SCRIPTS/ if the script
is directly in your PATH.
More information can be found here: https://unix.stackexchange.com/a/3064"
    exit 1
fi
}

network_ok() {
    echo "Testing if network is OK..."
    service network-manager restart
    if wget -q -T 20 -t 2 http://github.com -O /dev/null
    then
        return 0
    else
        return 1
    fi
}

check_command() {
  if ! "$@";
  then
     printf "${IRed}Sorry but something went wrong. Please report this issue to $ISSUES and include the output of the error message. Thank you!${Color_Off}\n"
     echo "$* failed"
    exit 1
  fi
}

# END OF FUNCTIONS #

# Check if root
root_check

# Check network
if network_ok
then
    printf "${Green}Online!${Color_Off}\n"
else
    echo "Setting correct interface..."
    [ -z "$IFACE" ] && IFACE=$(lshw -c network | grep "logical name" | awk '{print $3; exit}')
    # Set correct interface
cat <<-SETDHCP > "/etc/netplan/01-netcfg.yaml"
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: yes
      dhcp6: yes
SETDHCP
    check_command netplan apply
    check_command service network-manager restart
    ip link set "$IFACE" down
    wait
    ip link set "$IFACE" up
    wait
    check_command service network-manager restart
    echo "Checking connection..."
    sleep 3
    if ! nslookup github.com
    then
msg_box "Network NOT OK. You must have a working network connection to run this script
If you think that this is a bug, please report it to https://github.com/techandme/wordpress-vm/issues."
    exit 1
    fi
fi

# Check network again
if network_ok
then
    printf "${Green}Online!${Color_Off}\n"
else
msg_box "Network NOT OK. You must have a working network connection to run this script
If you think that this is a bug, please report it to https://github.com/techandme/wordpress-vm/issues."
    exit 1
fi

# shellcheck source=lib.sh
WPDB=1 && MYCNFPW=1 && FIRST_IFACE=1 && CHECK_CURRENT_REPO=1 . <(curl -sL https://raw.githubusercontent.com/techandme/wordpress-vm/master/lib.sh)
unset FIRST_IFACE
unset CHECK_CURRENT_REPO
unset MYCNFPW
unset WPDB

# Check where the best mirrors are and update
printf "\nTo make downloads as fast as possible when updating you should have mirrors that are as close to you as possible.\n"
echo "This VM comes with mirrors based on servers in that where used when the VM was released and packaged."
echo "We recomend you to change the mirrors based on where this is currently installed."
echo "Checking current mirror..."
printf "Your current server repository is:  ${Cyan}$REPO${Color_Off}\n"

# Check for errors + debug code and abort if something isn't right
# 1 = ON
# 0 = OFF
DEBUG=0
debug_mode

if [[ "no" == $(ask_yes_or_no "Do you want to try to find a better mirror?") ]]
then
    echo "Keeping $REPO as mirror..."
    sleep 1
else
    echo "Locating the best mirrors..."
    apt update -q4 & spinner_loading
    apt install python-pip -y
    pip install \
        --upgrade pip \
        apt-select
    apt-select -m up-to-date -t 5 -c
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup && \
    if [ -f sources.list ]
    then
        sudo mv sources.list /etc/apt/
    fi
fi

echo
echo "Getting scripts from GitHub to be able to run the first setup..."
# All the shell scripts in static (.sh)
download_static_script security
download_static_script update
download_static_script ip
download_static_script test_connection
download_static_script wp-permissions
download_static_script change_mysql_pass
download_static_script techandme
download_static_script index
download_le_script activate-ssl

# Make $SCRIPTS excutable
chmod +x -R $SCRIPTS
chown root:root -R $SCRIPTS

# Allow wordpress to run figlet script
chown wordpress:wordpress $SCRIPTS/techandme.sh

clear
cat << EOMSTART
+---------------------------------------------------------------+
|   This script will do the final setup for you                 |
|                                                               |
|   - Genereate new server SSH keys                             |
|   - Set static IP                                             |
|   - Create a new WP user                                      |
|   - Upgrade the system                                        |
|   - Activate SSL (Let's Encrypt)                              |
|   - Install Adminer                                           |
|   - Change keyboard setup (current is Swedish)                |
|   - Change system timezone                                    |
|   - Set new password to the Linux system (user: wordpress)    |
|                                                               |
|    ############### T&M Hansson IT AB - 2018 ###############   |
+---------------------------------------------------------------+
EOMSTART

any_key "Press any key to start the script..."
clear

# Set static IP
wget -q https://raw.githubusercontent.com/nextcloud/vm/master/static/set_static_ip.sh
bash set_static_ip.sh
rm -f set_static_ip.sh
clear

# Set keyboard layout
echo "Current keyboard layout is $(localectl status | grep "Layout" | awk '{print $3}')"
if [[ "no" == $(ask_yes_or_no "Do you want to change keyboard layout?") ]]
then
    echo "Not changing keyboard layout..."
    sleep 1
    clear
else
    dpkg-reconfigure keyboard-configuration
clear
fi

# Change Timezone
echo "Current timezone is $(cat /etc/timezone)"
if [[ "no" == $(ask_yes_or_no "Do you want to change timezone?") ]]
then
    echo "Not changing timezone..."
    sleep 1
    clear
else
    dpkg-reconfigure tzdata
clear
fi

# Generate new SSH Keys
printf "\nGenerating new SSH keys for the server...\n"
rm -v /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server

# Generate new MARIADB password
echo "Generating new MARIADB password..."
if bash "$SCRIPTS/change_mysql_pass.sh" && wait
then
   rm "$SCRIPTS/change_mysql_pass.sh"
fi

whiptail --title "Which apps do you want to install?" --checklist --separate-output "Automatically configure and install selected apps\nSelect by pressing the spacebar" "$WT_HEIGHT" "$WT_WIDTH" 4 \
"Fail2ban" "(Extra Bruteforce protection)   " OFF \
"Webmin" "(Server GUI)       " OFF \
"Adminer" "(*SQL GUI)       " OFF 2>results
while read -r -u 9 choice
do
    case $choice in
        Fail2ban)
            run_app_script fail2ban

        ;;

        Webmin)
            run_app_script webmin

        ;;

        Adminer)
            run_app_script adminer
        ;;

        *)
        ;;
    esac
done 9< results
rm -f results
clear

# Change password
printf "${Color_Off}\n"
echo "For better security, change the system user password for [$(getent group sudo | cut -d: -f4 | cut -d, -f1)]"
any_key "Press any key to change password for system user..."
while true
do
    sudo passwd "$(getent group sudo | cut -d: -f4 | cut -d, -f1)" && break
done
echo
clear

cat << LETSENC
+-----------------------------------------------+
|  The following script will install a trusted  |
|  SSL certificate through Let's Encrypt.       |
+-----------------------------------------------+
LETSENC
# Let's Encrypt
if [[ "yes" == $(ask_yes_or_no "Do you want to install SSL?") ]]
then
    bash $SCRIPTS/activate-ssl.sh
else
    echo
    echo "OK, but if you want to run it later, just type: sudo bash $SCRIPTS/activate-ssl.sh"
    any_key "Press any key to continue..."
fi

# Define FQDN and create new WP user
MYANSWER="no"
while [ "$MYANSWER" == "no" ] 
do
   clear
   cat << ENTERNEW
+-----------------------------------------------+
|    Please define the FQDN and create a new    |
|    user for Wordpress.                        |
|    Make sure your FQDN starts with either     |
|    http:// or https://, otherwise your        |
|    installation will not work correctly!      |
+-----------------------------------------------+
ENTERNEW
   echo "Enter FQDN (http(s)://yourdomain.com):"
   read -r FQDN
   echo
   echo "Enter username:"
   read -r USER
   echo
   echo "Enter password:"
   read -r NEWWPADMINPASS
   echo
   echo "Enter email address:"
   read -r EMAIL
   echo
   MYANSWER=$(ask_yes_or_no "Is this correct?  FQDN: $FQDN User: $USER Password: $NEWWPADMINPASS Email: $EMAIL") 
done
clear

echo "$FQDN" > fqdn.txt
wp_cli_cmd option update siteurl < fqdn.txt --path="$WPATH"
rm fqdn.txt

OLDHOME=$(wp_cli_cmd option get home --path="$WPATH")
wp_cli_cmd search-replace "$OLDHOME" "$FQDN" --precise --all-tables --path="$WPATH"

wp_cli_cmd user create "$USER" "$EMAIL" --role=administrator --user_pass="$NEWWPADMINPASS" --path="$WPATH"
wp_cli_cmd user delete 1 --reassign="$USER" --path="$WPATH"
{
echo "WP USER: $USER"
echo "WP PASS: $NEWWPADMINPASS"
} > /var/adminpass.txt

# Change servername in Nginx
server_name=$(echo "$FQDN" | cut -d "/" -f3)
sed -i "s|# server_name .*|server_name $server_name;|g" /etc/nginx/sites-available/wordpress_port_80.conf
sed -i "s|# server_name .*|server_name $server_name;|g" /etc/nginx/sites-available/wordpress_port_443.conf
check_command service nginx restart

# Show current administrators
echo
echo "This is the current administrator(s):"
wp_cli_cmd user list --role=administrator --path="$WPATH"
any_key "Press any key to continue..."
clear

# Fixes https://github.com/techandme/wordpress-vm/issues/58
a2dismod status
service apache2 reload

# Cleanup 1
rm -f "$SCRIPTS/ip.sh"
rm -f "$SCRIPTS/test_connection.sh"
rm -f "$SCRIPTS/instruction.sh"
rm -f "$SCRIPTS/wordpress-startup-script.sh"
find /root "/home/$UNIXUSER" -type f \( -name '*.sh*' -o -name '*.html*' -o -name '*.tar*' -o -name '*.zip*' \) -delete
sed -i "s|instruction.sh|techandme.sh|g" "/home/$UNIXUSER/.bash_profile"

truncate -s 0 \
    /root/.bash_history \
    "/home/$UNIXUSER/.bash_history" \
    /var/spool/mail/root \
    "/var/spool/mail/$UNIXUSER" \
    /var/log/apache2/access.log \
    /var/log/apache2/error.log \
    /var/log/cronjobs_success.log

sed -i "s|sudo -i||g" "/home/$UNIXUSER/.bash_profile"
cat << RCLOCAL > "/etc/rc.local"
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0

RCLOCAL
clear

# Upgrade system
echo "System will now upgrade..."
bash $SCRIPTS/update.sh

# Cleanup 2
apt autoremove -y
apt autoclean

ADDRESS2=$(grep "server_name" /etc/nginx/sites-available/wordpress_port_80.conf | awk '$1 == "server_name" { print $2 }' | cut -d ";" -f1)
# Success!
clear
printf "%s\n""${Green}"
echo    "+--------------------------------------------------------------------+"
echo    "|      Congratulations! You have successfully installed Wordpress!   |"
echo    "|                                                                    |"
printf "|         ${Color_Off}Login to Wordpress in your browser: ${Cyan}\"$ADDRESS2\"${Green}         |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}Publish your server online! ${Cyan}https://goo.gl/iUGE2U${Green}          |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}To login to MARIADB just type: ${Cyan}'mysql -u root'${Green}             |\n"
echo    "|                                                                    |"
printf "|         ${Color_Off}To update this VM just type: ${Green}                              |\n"
printf "|         ${Cyan}'sudo bash /var/scripts/update.sh'${Green}                         |\n"
echo    "|                                                                    |"
printf "|    ${IRed}################ T&M Hansson IT AB - 2018 ################${Green}      |\n"
echo    "+--------------------------------------------------------------------+"
printf "${Color_Off}\n"

# Prefer IPv6
sed -i "s|precedence ::ffff:0:0/96  100|#precedence ::ffff:0:0/96  100|g" /etc/gai.conf

## Reboot
echo "Installations finished. System will now reboot..."
reboot
