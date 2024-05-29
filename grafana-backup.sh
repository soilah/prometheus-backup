
#!/bin/bash
source ./utils.sh


DATE_SUFFIX=$(date +%F_%H%M%S)
GRAFANA_CONFIG_DIR=$(dirname $(systemctl --full --no-pager status grafana-server | grep "config" | awk -F'--config' '{print $2}' | sed 's/^[= ]//g' | cut -d" " -f1))
GRAFANA_DATA_DIR=$(systemctl --full --no-pager status grafana-server | grep "paths.data" | awk -F'paths.data' '{print $2}' | sed 's/^[= ]//g' | cut -d" " -f1)
BACKUP_DIR="/var/backups/grafana-BACKUP/grafana$DATE_SUFFIX"
BACKUP_DATA=true
BACKUP_DIR_INITIALIZED=false
BACKUP_INCREMENTAL=false
FORCE_BACKUP=false
BD_TYPE="sqlite3"

print_help() {
	echo ./$(basename $0) [OPTIONS]
	echo -e "\n\tOPTIONS:\n\t-h\t\t\t\t\tShow this help message"
	echo -e "\t-B|--backup-dir backup directory\tSpecify a custom backup directory"
	echo -e "\t-C|--config-dir config directory\tSpecify grafana config directory if not default. Default is taken from systemd configuration"
	echo -e "\t-D|--data-dir data directory\tSpecify grafana data directory if not default. Default is taken from systemd configuration"
	echo -e "\t-I|--incremental \t Perform an incremental backup. Backup files (config and data) that are newer than the latest versions inside the backup directory"
	echo -e "\t-S|--no-data \t\t\t\tSave configuration only without data folder"
	echo -e "\t-F|--force \t\t\t\tDo not interactively show prompt to user."
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

db_backup() {
	# Default is sqlite3
	cat /etc/grafana/grafana.ini | grep "type\ =\ mysql" &>/dev/null
	if [ $? -eq 0 ]; then
		info 'Detected MYSQL database... Exporting database...'
		USER=$(cat /etc/grafana/grafana.ini  | grep "\[database\]" -A 70 | grep -e "user.*=" | cut -d'=' -f2 | tr -d " ")
		PASSWORD=$(cat /etc/grafana/grafana.ini  | grep "\[database\]" -A 70 | grep -e "password.*=" | cut -d'=' -f2 | tr -d " ")
		DB_NAME=$(cat /etc/grafana/grafana.ini  | grep "\[database\]" -A 70 | grep -e "name.*=" | cut -d'=' -f2 | tr -d " ")
		#DB_HOST=$(cat /etc/grafana/grafana.ini  | grep "\[database\]" -A 70 | grep -e "host.*=" | cut -d'=' -f2 | tr -d " ")
		mysqldump -u$USER -p$PASSWORD $DB_NAME > grafana_backup.sql
		ok "OK"
		info "Backing up database file..."
		rsync -a grafana_backup.sql $BACKUP_DIR/data
		rm grafana_backup.sql &>/dev/null
	else
		info 'Detected SQLite3 database... Exporting database...'
		rsync -a $GRAFANA_DATA_DIR/grafana.db $BACKUP_DIR/data
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
				info "Directory $BACKUP_DIR_PARENT does not exist. Creating it..."
				#error "Directory $BACKUP_DIR_PARENT does not exist. Exiting."
				mkdir $BACKUP_DIR_PARENT
			fi
			test -w $BACKUP_DIR_PARENT
			if [ $? -eq 0 ]; then
				if [ "${2: -1}" == "/" ]; then BACKUP_DIR="$BACKUP_DIR_PARENT/grafana_BACKUP/grafana"; else BACKUP_DIR="$BACKUP_DIR_PARENT/grafana_BACKUP/grafana"; fi
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
		-D|--data-dir)
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
		-S|--no-data)
			BACKUP_DATA=false
			shift 1
			;;
		--victoriametrics)
			BACKUP_VICTORIAMETRICS=true
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
	if [[ $BACKUP_DIR_INITIALIZED = 'false' ]]; then
		BACKUP_DIR=/home/$(whoami)/grafana-BACKUP/grafana/$DATE_SUFFIX
		check_backup_dir_create $BACKUP_DIR
		BACKUP_DIR_INITIALIZED=true
	fi
fi



	

if [ ! -d $GRAFANA_CONFIG_DIR ]; then
	error "Error finding configuration directory. Exiting."
	exit
fi

if [ ! -d $GRAFANA_DATA_DIR ]; then
	error "Error finding data directory. Exiting."
	exit
fi

info "Configuration directory: $GRAFANA_CONFIG_DIR"
if [[ $BACKUP_DATA = 'true' ]]; then
	info "Data directory: $GRAFANA_DATA_DIR"
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
info "Backing up grafana configurations..."
rsync -a $GRAFANA_CONFIG_DIR/* $BACKUP_DIR/config
ok "Done"

if [[ "$BACKUP_DATA" = true ]]; then
	
	info "Backing up grafana data..."
	db_backup
	ok "Done"

fi

ok "Backup successful!"
