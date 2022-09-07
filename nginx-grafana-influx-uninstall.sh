#!/bin/bash

# Nginx, Grafana, and InfluxDB Installer Script Remover (v1.0.0) by lilciv#2944

#Root user check
RootCheck() {
    if [ "$EUID" -ne 0 ]
      then echo "Current user is not root! Please rerun this script as the root user."
      exit
    else
      Confirm
    fi
}

Confirm() {
    clear
    echo "This will delete your Grafana, InfluxDB, and Nginx instances! Be sure you want to continue."
    read -s -n 1 -p "Press any key to continue . . ."
    echo ""
    DeleteContainers
}

#Delete Containers
DeleteContainers() {
    docker stop Grafana
    docker stop InfluxDB
    docker stop Nginx
    docker rm Grafana
    docker rm InfluxDB
    docker rm Nginx
    Data
}

#Keep Data?
Data() {
    read -n1 -p "Delete all data? [y,n]" choice 
    case $choice in  
      y|Y) DeleteData ;; 
      n|N) exit ;; 
      *) exit ;; 
    esac
}

#Delete all data!
DeleteData() {
    rm -rf Docker
}

RootCheck
