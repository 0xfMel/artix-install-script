if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

curl -OL https://github.com/0xfMel/artix-install-script/archive/master.tar.gz
tar -xvzf master.tar.gz
cd artix-install-script-master
sh ./scripts/install.sh
