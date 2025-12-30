#!/usr/bin/env bash

set -euo pipefail

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# ---------- AWS / Infra Config (EDIT THESE) ----------
AWS_REGION="us-east-1"         # e.g. us-east-1
AMI_ID="ami-0b4f379183e5706b9" # TODO: put your AMI ID here (Amazon Linux 2, etc.)
# SUBNET_ID="subnet-xxxxxxxx"     # TODO: your subnet ID
SECURITY_GROUP_ID="sg-04357080f8248528a" # TODO: your security group ID
KEY_NAME="ansible_practice_keypair"      # TODO: your EC2 key pair name

HOSTED_ZONE_ID="Z06046792KQ5HDP2YEDR4" # TODO: Route53 hosted zone ID for optimusprime.sbs
DOMAIN_NAME="optimusprime.sbs"

# Microservices list
SERVICES=(web)

# Instance type mapping
declare -A INSTANCE_TYPES
INSTANCE_TYPES=(
	[web]="t2.micro"

)

# Will hold instance IDs and IPs
declare -A INSTANCE_IDS
declare -A PRIVATE_IPS
declare -A PUBLIC_IPS

# ---------- Paths & Logs ----------
TIMESTAMP="$(date +"%F-%H-%M-%S")"

roboshop_app_dir="/app"
roboshop_log_dir="${roboshop_app_dir}/log"

SCRIPT_NAME="$(basename "$0")"
SCRIPT_BASE="${SCRIPT_NAME%.*}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${roboshop_log_dir}/${SCRIPT_BASE}-$(date +%F).log"

printBoxHeader() {
	local TITLE="$1"
	local TIME="$2"

	echo -e "${BLUE}===========================================${RESET}"
	printf "${CYAN}%20s${RESET}\n" "$TITLE"
	printf "${YELLOW}%20s${RESET}\n" "Started @ $TIME"
	echo -e "${BLUE}===========================================${RESET}"
}

# ---------- Helper: validate step ----------
validateStep() {
	local STATUS="$1"
	local SUCCESS_MSG="$2"
	local FAILURE_MSG="$3"

	if [[ "${STATUS}" -eq 0 ]]; then
		echo -e "${GREEN}[SUCCESS]${RESET} ${SUCCESS_MSG}"
	else
		echo -e "${RED}[FAILURE]${RESET} ${FAILURE_MSG} (exit code: ${STATUS})"
		exit "${STATUS}"
	fi
}

# ---------- Root / sudo handling ----------
isItRootUser() {
	echo -e "${CYAN}Checking whether script is running as ROOT...${RESET}"

	if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
		if command -v sudo >/dev/null 2>&1; then
			SUDO="sudo"
			echo -e "${YELLOW}Not ROOT. Using 'sudo' for privileged operations.${RESET}"
		else
			echo -e "${RED}ERROR: Insufficient privileges. Run as ROOT or install sudo.${RESET}"
			exit 1
		fi
	else
		SUDO=""
		echo -e "${GREEN}Executing this script as ROOT user.${RESET}"
	fi
}

# ---------- Check AWS CLI ----------
checkAwsCli() {
	echo -e "${CYAN}Checking AWS CLI availability...${RESET}"
	if ! command -v aws >/dev/null 2>&1; then
		echo -e "${RED}AWS CLI is not installed or not in PATH. Install awscli v2 first.${RESET}"
		exit 1
	fi

	# Optional: show identity & region
	echo -e "${CYAN}AWS caller identity...${RESET}"
	aws sts get-caller-identity || echo -e "${YELLOW}Warning: Unable to get caller identity (check IAM role).${RESET}"

	echo -e "${CYAN}Using AWS Region: ${AWS_REGION}${RESET}"
}

# ---------- Launch EC2 instances ----------
launchEc2Instances() {
	echo -e "${CYAN}Launching EC2 instances for Roboshop microservices...${RESET}"
	echo -e "${YELLOW}AMI_ID=${AMI_ID}, SG=${SECURITY_GROUP_ID}, KEY_NAME=${KEY_NAME}${RESET}"

	for svc in "${SERVICES[@]}"; do
		local itype="${INSTANCE_TYPES[$svc]}"

		echo -e "${BLUE}-------------------------------------------${RESET}"
		echo -e "${CYAN}Launching service: ${svc} (Instance type: ${itype})${RESET}"

		# NOTE: set +e so we can handle failures with validateStep
		set +e
		instance_id=$(aws ec2 run-instances \
			--region "${AWS_REGION}" \
			--image-id "${AMI_ID}" \
			--instance-type "${itype}" \
			--security-group-ids "${SECURITY_GROUP_ID}" \
			--key-name "${KEY_NAME}" \
			--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${svc}},{Key=Project,Value=roboshop}]" \
			--query 'Instances[0].InstanceId' \
			--output text 2>&1)
		rc=$?
		set -e

		if [[ ${rc} -ne 0 ]]; then
			echo -e "${RED}EC2 run-instances failed for ${svc}:${RESET} ${instance_id}"
			exit ${rc}
		fi

		# instance_id variable contains either the ID or an error; sanity check:
		if [[ "${instance_id}" != i-* ]]; then
			echo -e "${RED}Unexpected instance ID for ${svc}: ${instance_id}${RESET}"
			exit 1
		fi

		INSTANCE_IDS["$svc"]="${instance_id}"
		echo -e "${GREEN}${svc}: Launched instance ${instance_id}${RESET}"

		echo -e "${CYAN}Waiting for ${instance_id} to reach 'running' state...${RESET}"
		aws ec2 wait instance-running \
			--region "${AWS_REGION}" \
			--instance-ids "${instance_id}"
		validateStep $? \
			"${svc} instance is now running." \
			"Error while waiting for ${svc} instance to be running."

		# Fetch Private and Public IPs
		private_ip=$(aws ec2 describe-instances \
			--region "${AWS_REGION}" \
			--instance-ids "${instance_id}" \
			--query 'Reservations[0].Instances[0].PrivateIpAddress' \
			--output text)
		public_ip=$(aws ec2 describe-instances \
			--region "${AWS_REGION}" \
			--instance-ids "${instance_id}" \
			--query 'Reservations[0].Instances[0].PublicIpAddress' \
			--output text)

		PRIVATE_IPS["$svc"]="${private_ip}"
		PUBLIC_IPS["$svc"]="${public_ip}"

		echo -e "${GREEN}${svc}: Private IP = ${private_ip}, Public IP = ${public_ip}${RESET}"
	done
}

# ---------- Route53 Helper ----------
createRoute53ARecord() {
	local name="$1"
	local value="$2"

	echo -e "${CYAN}Creating/Updating Route53 A record: ${name} -> ${value}${RESET}"

	set +e
	aws route53 change-resource-record-sets \
		--hosted-zone-id "${HOSTED_ZONE_ID}" \
		--change-batch "{
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"${name}\",
          \"Type\": \"A\",
          \"TTL\": 1,
          \"ResourceRecords\": [
            {\"Value\": \"${value}\"}
          ]
        }
      }]
    }" >/dev/null 2>&1
	rc=$?
	set -e

	validateStep ${rc} \
		"Route53 record created/updated: ${name} -> ${value}" \
		"Failed to create Route53 A record for ${name}"
}

# ---------- Create Route53 records ----------
createRoute53Records() {
	echo -e "${CYAN}Creating Route53 A records for optimusprime.sbs and microservices...${RESET}"

	# Root domain -> use WEB public IP (common pattern)
	local root_ip="${PUBLIC_IPS[web]:-}"
	if [[ -z "${root_ip}" || "${root_ip}" == "None" ]]; then
		echo -e "${YELLOW}Warning: No public IP found for 'web' service. Skipping ${DOMAIN_NAME} root A record.${RESET}"
	else
		createRoute53ARecord "${DOMAIN_NAME}" "${root_ip}"
	fi

	# Microservice subdomains -> use Private IPs
	for svc in "${SERVICES[@]}"; do
		local priv_ip="${PRIVATE_IPS[$svc]:-}"
		local fqdn="${svc}.${DOMAIN_NAME}"

		if [[ -z "${priv_ip}" || "${priv_ip}" == "None" ]]; then
			echo -e "${YELLOW}Warning: No private IP for ${svc}. Skipping DNS for ${fqdn}.${RESET}"
			continue
		fi

		createRoute53ARecord "${fqdn}" "${priv_ip}"
	done
}

# ---------- Summary ----------
printSummary() {
	echo -e "${BLUE}================= SUMMARY =================${RESET}"
	echo -e "${CYAN}Service\t\tInstance ID\t\tPrivate IP\tPublic IP${RESET}"
	for svc in "${SERVICES[@]}"; do
		printf "%-10s\t%-20s\t%-15s\t%-15s\n" \
			"${svc}" \
			"${INSTANCE_IDS[$svc]:-N/A}" \
			"${PRIVATE_IPS[$svc]:-N/A}" \
			"${PUBLIC_IPS[$svc]:-N/A}"
	done
	echo -e "${BLUE}===========================================${RESET}"
}

# ---------- Main ----------
main() {
	mkdir -p "${roboshop_log_dir}"

	# Send stdout+stderr to log file
	exec >>"${LOG_FILE}" 2>&1

	printBoxHeader "Roboshop Infra Script Execution" "${TIMESTAMP}"
	echo "App Directory       : ${roboshop_app_dir}"
	echo "Log Directory       : ${roboshop_log_dir}"
	echo "Log File            : ${LOG_FILE}"
	echo "Script Directory    : ${SCRIPT_DIR}"
	echo "AWS Region          : ${AWS_REGION}"
	echo "Domain Name         : ${DOMAIN_NAME}"
	echo "Hosted Zone ID      : ${HOSTED_ZONE_ID}"

	echo -e "\n${CYAN}Calling isItRootUser() to validate the user...${RESET}"
	isItRootUser

	echo -e "\n${CYAN}Checking AWS CLI and IAM Role....${RESET}"
	checkAwsCli

	echo -e "\n${CYAN}Launching EC2 instances for all Roboshop microservices....${RESET}"
	launchEc2Instances

	echo -e "\n${CYAN}Creating Route53 DNS records for all microservices....${RESET}"
	createRoute53Records

	echo -e "\n${CYAN}Printing summary....${RESET}"
	printSummary

	echo -e "\n${GREEN}Roboshop Infra setup script completed successfully.${RESET}"
}

main "$@"
