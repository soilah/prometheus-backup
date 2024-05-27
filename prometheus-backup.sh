#!/bin/bash
source ./utils.sh


DATE_SUFFIX=$(date +%F_%H%M%S)
PROMETHEUS_CONFIG_DIR=$(dirname $(systemctl --full --no-pager status prometheus | grep "config.file" | awk -F'--config.file' '{print $2}' | tr -d " " | cut -d'-' -f1 ))
PROMETHEUS_DATA_DIR=$(systemctl --full --no-pager status prometheus | grep "storage.tsdb.path" | awk -F'--storage.tsdb.path' '{print $2}' | tr -d " " | cut -d'-' -f1 )
BACKUP_DIR="/var/backups/prometheus-BACKUP/prometheus$DATE_SUFFIX"
BACKUP_DIR_PARENT="~/prometheus-BACKUP"
BACKUP_DATA=true
BACKUP_DIR_INITIALIZED=false
BACKUP_INCREMENTAL=false
FORCE_BACKUP=false

print_help() {
	echo ./$(basename $0) [OPTIONS]
	echo -e "\n\tOPTIONS:\n\t-h\t\t\t\t\tShow this help message"
	echo -e "\t-B|--backup-dir backup directory\tSpecify a custom backup directory"
	echo -e "\t-C|--config-dir config directory\tSpecify prometheus config directory if not default. Default is taken from systemd configuration"
	echo -e "\t-D|--data-dir data directory\tSpecify prometheus data directory if not default. Default is taken from systemd configuration"
	echo -e "\t-I|--incremental \t Perform an incremental backup. Backup files (config and data) that are newer than the latest versions inside the backup directory"
	echo -e "\t-S|--no-data \t\t\t\tSave configuration only without data folder"
}

check_backup_dir_create () {
	BACKUP_DIR=$1
	if [[ -d $BACKUP_DIR ]] && [[ $BACKUP_INCREMENTAL = 'false' ]]; then
		if [[ -z $(ls -A $BACKUP_DIR) ]]; then
			ok "Directory already exists but is empty... proceeding"
		else
			error "Directory $BACKUP_DIR already exists and is not empty. Exiting."
			exit
		fi
	else
		info "Creating backup directory..."
		mkdir -p $BACKUP_DIR"/config"
		mkdir -p $BACKUP_DIR"/data"
	fi
}

check_args() {
	# read the options
	options=$(getopt -o hIBF:SC:D: --long help,incremental,force,backup-dir:,no-data,config-dir:,data-dir: -- "$@")
	eval set -- "$options"

	# extract options and their arguments into variables.
	while true ; do
		case "$1" in
		-h|--help)
			print_help ; exit
			;;
		-I|--incremental)
			BACKUP_INCREMENTAL=true
			shift 1
			;;
		-F|--force)
			FORCE_BACKUP=true
			shift 1
			;;
		-B|--backup-dir)
			BACKUP_DIR_PARENT=$2
			if [[ ! -d $BACKUP_DIR_PARENT ]]; then
				error "Directory $BACKUP_DIR_PARENT does not exist. Exiting."
				exit
			fi
			test -w $BACKUP_DIR_PARENT
			if [ $? -eq 0 ]; then
				if [ "${2: -1}" == "/" ]; then BACKUP_DIR="$BACKUP_DIR_PARENT/prometheus_BACKUP/prometheus"; else BACKUP_DIR="$BACKUP_DIR_PARENT/prometheus_BACKUP/prometheus"; fi
				check_backup_dir_create $BACKUP_DIR
				BACKUP_DIR_INITIALIZED=true
			else
				error "User $(whoami) does not have write permissions on $BACKUP_DIR_PARENT. Exiting."
				exit
			fi
			shift 2
			;;
			#if [ -d "$2/ ] then echo "Directory already exists..." 
		-C|--config-dir)
			if [ -d $2 ]; then
				test -r $2
				if [ $? -eq 0 ]; then
					PROMETHEUS_CONFIG_DIR=$2
				else
					error "User $(whoami) does not have read permissions on $2. Exiting."
					exit
				fi
			else
				error "Specified config directory does not exist. Exiting."
				exit
			fi
			shift 2
			;;
		-D|--data-dir)
			if [ -d $2 ]; then
				test -r $2
				if [ $? -eq 0 ]; then
					PROMETHEUS_DATA_DIR=$2
				else
					error "User $(whoami) does not have read permissions on $2. Exiting."
					exit
				fi
			else
				error "Specified data directory does not exist. Exiting."
				exit
			fi
			shift 2
			;;
		-S|--no-data)
			BACKUP_DATA=false
			shift 1
			;;
		--) shift; break
			;;
		*) echo "Internal error!" ; exit 1 ;;
		esac
	done
}



check_args "$@"

USER=$(whoami)

if [[ $USER != "root" ]]; then 
	if [[ $BACKUP_DATA = "true" ]] && [[ $FORCE_BACKUP = 'false' ]]; then
		info 'In order to safely backup data directory, the prometheus service needs to be stopped and that can only be done with the root user. It is not recommended to proceed without root rights if you want to backup the prometheus data directory.'
		ANS=$(prompt_yes_no 'Do you want to unsafely try to backup the data directory? (yes/no): ')
		if [[ $ANS = 'no' ]]; then
			BACKUP_DATA=false
			ok "Good."
		else
			info "OK..."
		fi
	fi
	if [[ $BACKUP_DIR_INITIALIZED = 'false' ]]; then
		BACKUP_DIR=/home/$(whoami)/prometheus-BACKUP/prometheus/$DATE_SUFFIX
		check_backup_dir_create $BACKUP_DIR
		BACKUP_DIR_INITIALIZED=true
	fi
fi



	

if [ ! -d $PROMETHEUS_CONFIG_DIR ]; then
	error "Error finding configuration directory. Exiting."
	exit
fi

if [ ! -d $PROMETHEUS_DATA_DIR ]; then
	error "Error finding data directory. Exiting."
	exit
fi

info "Configuration directory: $PROMETHEUS_CONFIG_DIR"
if [[ $BACKUP_DATA = 'true' ]]; then
	info "Data directory: $PROMETHEUS_DATA_DIR"
fi
info "Using $BACKUP_DIR as backup directory."


if [[ $FORCE_BACKUP = 'false' ]]; then
	ANS=$(prompt_yes_no "Check if the above are correct before proceeding. Continue? (yes/no): ")
	if [ "$ANS" == "no" ]; then
		error "Exiting..."
		exit
	fi
fi

[[ "$BACKUP_DIR_INITIALIZED" = false ]] && check_backup_dir_create $BACKUP_DIR




info "STARTING BACKUP"
info "Backing up prometheus configurations..."
rsync -a $PROMETHEUS_CONFIG_DIR/* $BACKUP_DIR/config
ok "Done"

if [ "$BACKUP_DATA" = true ]; then
	
	if [[ $USER = 'root' ]]; then
		info "Stopping prometheus service..."
		systemctl stop prometheus &> /dev/null

		STATUS=$(systemctl is-active prometheus)
		if [ "$STATUS" == "active" ]; then
			error "Could not stop prometheus service... Stop it manually an re run backup script"
			exit
		fi
	fi

	info "Backing up prometheus data..."
	rsync -r $PROMETHEUS_DATA_DIR/* $BACKUP_DIR/data
	ok "Done"


	if [[ $USER = 'root' ]]; then
		info "Starting prometheus service..."
		systemctl start prometheus &> /dev/null

		STATUS=$(systemctl is-active prometheus)
		if [ "$STATUS" == "inactive" ]; then
			error "Could not restart prometheus service. Start it manually."
		fi
	fi
fi

ok "Backup successful!"
