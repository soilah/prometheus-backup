#!/bin/bash
source ./utils.sh


DATE_SUFFIX=$(date +%F_%H%M%S)
PROMETHEUS_CONFIG_DIR=
PROMETHEUS_DATA_DIR=
ALERTMANAGER_CONFIG_DIR=
GRAFANA_CONFIG_DIR=
GRAFANA_DATA_DIR=
BACKUP_DIR="/var/backups/prometheus_suite-BACKUP$DATE_SUFFIX"
#BACKUP_DIR_PARENT="~/prometheus_suite-BACKUP"
BACKUP_DATA=true
BACKUP_DIR_INITIALIZED=false
BACKUP_INCREMENTAL=false
FORCE_BACKUP=false

print_help() {
	echo ./$(basename $0) [OPTIONS]
	echo -e "\n\tOPTIONS:\n\t-h\t\t\t\t\tShow this help message"
	echo -e "\t-B|--backup-dir backup directory\tSpecify a custom backup directory"
	echo -e "\t--prometheus-config-dir prometheus config directory\tSpecify prometheus config directory if not default. Default is taken from systemd configuration"
	echo -e "\t--alertmanager-config-dir prometheus config directory\tSpecify alertmanager config directory if not default. Default is taken from systemd configuration"
	echo -e "\t--prometheus-data-dir data directory\tSpecify prometheus data directory if not default. Default is taken from systemd configuration"
	echo -e "\t--grafana-config-dir prometheus config directory\tSpecify grafana config directory if not default. Default is taken from systemd configuration"
	echo -e "\t--grafana-data-dir data directory\tSpecify grafana data directory if not default. Default is taken from systemd configuration"
	echo -e "\t-I|--incremental \t Perform an incremental backup. Backup files (config and data) that are newer than the latest versions inside the backup directory"
	echo -e "\t-S|--no-data \t\t\t\tSave configuration only without data folder"
	echo -e "\t-F|--force \t\t\t\tDo not interactively show prompt to user."
}



check_args() {
	# read the options
	options=$(getopt -o hIBF:S: --long help,incremental,force,backup-dir:,no-data,prometheus-config-dir:,prometheus-data-dir:,grafana-config-dir:,grafana-data-dir:,alertmanager-config-dir: -- "$@")
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
				info "Directory $BACKUP_DIR_PARENT does not exist. Creating it..."
				#error "Directory $BACKUP_DIR_PARENT does not exist. Exiting."
				mkdir $BACKUP_DIR_PARENT
			fi
			test -w $BACKUP_DIR_PARENT
			if [ $? -eq 0 ]; then
				if [ "${2: -1}" == "/" ]; then BACKUP_DIR="$BACKUP_DIR_PARENT/prometheus_suite_BACKUP"; else BACKUP_DIR="$BACKUP_DIR_PARENT/prometheus_suite_BACKUP"; fi
			else
				error "User $(whoami) does not have write permissions on $BACKUP_DIR_PARENT. Exiting."
				exit
			fi
			shift 2
			;;
			#if [ -d "$2/ ] then echo "Directory already exists..." 
		--prometheus-config-dir)
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
		--prometheus-data-dir)
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
		--grafana-config-dir)
			if [ -d $2 ]; then
				test -r $2
				if [ $? -eq 0 ]; then
					GRAFANA_CONFIG_DIR=$2
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
		--grafana-data-dir)
			if [ -d $2 ]; then
				test -r $2
				if [ $? -eq 0 ]; then
					GRAFANA_DATA_DIR=$2
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
		--alertmanager-config-dir)
			if [ -d $2 ]; then
				test -r $2
				if [ $? -eq 0 ]; then
					alertmanager_CONFIG_DIR=$2
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

PROMETHEUS_OPTIONS=""
ALERTMANAGER_OPTIONS=""
GRAFANA_OPTIONS=""

if [[ ! -z "$PROMETHEUS_CONFIG_DIR" ]]; then
	PROMETHEUS_OPTIONS="${PROMETHEUS_OPTIONS} --config-dir $PROMETHEUS_CONFIG_DIR" 
fi

if [[ ! -z "$PROMETHEUS_DATA_DIR" ]]; then
	PROMETHEUS_OPTIONS="${PROMETHEUS_OPTIONS} --data-dir $PROMETHEUS_DATA_DIR" 
fi

if [[ ! -z "$GRAFANA_CONFIG_DIR" ]]; then
	GRAFANA_OPTIONS="${GRAFANA_OPTIONS} --config-dir $GRAFANA_CONFIG_DIR" 
fi

if [[ ! -z "$GRAFANA_DATA_DIR" ]]; then
	GRAFANA_OPTIONS="${GRAFANA_OPTIONS} --data-dir $GRAFANA_DATA_DIR" 
fi

if [[ ! -z "$ALERTMANAGER_CONFIG_DIR" ]]; then
	ALERTMANAGER_OPTIONS="${ALERTMANAGER_OPTIONS} --config-dir $ALERTMANAGER_CONFIG_DIR" 
fi

if [[ "$BACKUP_INCREMENTAL" = true ]]; then
	PROMETHEUS_OPTIONS="${PROMETHEUS_OPTIONS} --incremental"
	GRAFANA_OPTIONS="${GRAFANA_OPTIONS} --incremental"
	ALERTMANAGER_OPTIONS="${ALERTMANAGER_OPTIONS} --incremental"
fi

if [[ "$FORCE_BACKUP" = true ]]; then
	PROMETHEUS_OPTIONS="${PROMETHEUS_OPTIONS} --force"
	GRAFANA_OPTIONS="${GRAFANA_OPTIONS} --force"
	ALERTMANAGER_OPTIONS="${ALERTMANAGER_OPTIONS} --force"
fi

if [[ "$BACKUP_DATA" = false ]]; then
	PROMETHEUS_OPTIONS="${PROMETHEUS_OPTIONS} --no-data"
	GRAFANA_OPTIONS="${GRAFANA_OPTIONS} --no-data"
fi

PROMETHEUS_OPTIONS="${PROMETHEUS_OPTIONS} --backup-dir $BACKUP_DIR"
GRAFANA_OPTIONS="${GRAFANA_OPTIONS} --backup-dir $BACKUP_DIR"
ALERTMANAGER_OPTIONS="${ALERTMANAGER_OPTIONS} --backup-dir $BACKUP_DIR"

#echo "PROMETHEUS OPTIONS: $PROMETHEUS_OPTIONS"
#echo "GRAFANA OPTIONS: $GRAFANA_OPTIONS"
#echo "ALERTMANAGER OPTIONS: $ALERTMANAGER_OPTIONS"



info "======================= PROMETHEUS BACKUP ======================="
./prometheus-backup.sh $PROMETHEUS_OPTIONS
ok "======================= PROMETHEUS BACKUP ======================="
info "======================= ALERTMANAGER BACKUP ======================="
./alertmanager-backup.sh $ALERTMANAGER_OPTIONS
ok "======================= ALERTMANAGER BACKUP ======================="
info "======================= GRAFANA BACKUP ======================="
./grafana-backup.sh $GRAFANA_OPTIONS
ok "======================= GRAFANA BACKUP ======================="
