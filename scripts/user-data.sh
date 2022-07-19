#!/bin/bash

# first is Alvaro
cat >> /home/ubuntu/.ssh/authorized_keys <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDBzMaSE9ORQsJoIi+UrMQ+U8WFSpiYFXIKSvqFWbqyhpEM6MSoidX09CuvYIVPMtTeZZj/ZO+o+nL0TffIDNzkGgalhdlw5RL9OgJXgmUNWjW4VwIoR96D7TcP6EUyXkD0wxSgjryJSn4aONR3tIIYvHdM9YjRrivLlS/N7WzIRM6xvWJ8UK7fVYdD3V6FMp4+a33Uc+Ezk8XPWCvDt5vXluFPiKa8RlU7XXqPqI2bR89VJ5cpCnZorVtjVVlvgtOFdY/5hT7qqX1hxQyARkSLcnJiVylL3H3arDlnT/6nO71WY2/ZfyVUbQqcTC12UpFSJRH7JRCgf0stTdfzugCsq61XCMkZBfZ2OTBWeO8Qm2yDW7d4NwzKj31xKqDxT3sr7Gz6qiJO0XhaEjgBSAFB41hVDaNR8Fa6Ir1DObVQ+QsHOv4m2xhh8XxLaZZh30KWZNFAxVmeXoec0paDuj53UTM/ddhbKQr+8vPkbdlR4p5hxSSoVH+SBNLmGY4+K+0= kikitux@kikitux-C02ZR1GLLVDM
EOF

# wait until archive is available. Wait until there is internet before continue
until ping -c1 archive.ubuntu.com &>/dev/null; do
 echo "waiting for networking to initialise"
 sleep 3 
done 

# install monitoring tools
apt-get update
apt-get install -y ctop net-tools sysstat

# Set swappiness
if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi

if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
  echo never > /sys/kernel/mm/transparent_hugepage/defrag
fi

# heavy swap vm.swappiness=80
# no swap vm.swappiness=1
sysctl vm.swappiness=1
sysctl vm.min_free_kbytes=67584
sysctl vm.drop_caches=1
# make it permanent over server reboots
echo vm.swappiness=1 >> /etc/sysctl.conf
echo vm.min_free_kbytes=67584 >> /etc/sysctl.conf


# we get a list of disk
DISKS=($(lsblk  -p -I 259 -n -o SIZE | tail +3 | tr -d 'G'))

if [ $${DISKS[1]} -gt $${DISKS[0]} ]; then
	SWAP="/dev/nvme1n1"
	DOCKER="/dev/nvme2n1"
else
	SWAP="/dev/nvme2n1"
	DOCKER="/dev/nvme1n1"
fi

# swap
# if SWAP exists
# we format if no format
if [ -b $SWAP ]; then
	blkid $SWAP
	if [ $? -ne 0 ]; then
		mkswap $SWAP
	fi
fi

# if SWAP not in fstab
# we add it
grep "$SWAP" /etc/fstab
if [ $? -ne 0 ]; then
	echo "$SWAP swap swap defaults 0 0" | tee -a /etc/fstab
	swapon -a
fi

# docker
# if DOCKER exists
# we format if no format
if [ -b $DOCKER ]; then
	blkid $DOCKER
	if [ $? -ne 0 ]; then
		mkfs.xfs $DOCKER
	fi
fi

# if DOCKER not in fstab
# we add it
grep "$DOCKER" /etc/fstab
if [ $? -ne 0 ]; then
	echo "$DOCKER /var/lib/docker xfs defaults 0 0" | tee -a /etc/fstab
	mkdir -p /var/lib/docker
	mount -a
fi

# Netdata will be listening on port 19999
curl -sL https://raw.githubusercontent.com/automodule/bash/main/install_netdata.sh | bash

# install requirements for tfe
apt-get update

# Download all the software and files needed
apt-get -y install awscli
aws s3 cp s3://${tag_prefix}-software/${filename_license} /tmp/${filename_license}
aws s3 cp s3://${tag_prefix}-software/certificate_pem /tmp/certificate_pem
aws s3 cp s3://${tag_prefix}-software/issuer_pem /tmp/issuer_pem
aws s3 cp s3://${tag_prefix}-software/private_key_pem /tmp/server.key

# Create a full chain from the certificates
cat /tmp/certificate_pem >> /tmp/server.crt
cat /tmp/issuer_pem >> /tmp/server.crt

# create the configuration file for replicated installation
cat > /tmp/tfe_settings.json <<EOF
{
   "aws_instance_profile": {
        "value": "1"
    },
    "enc_password": {
        "value": "${tfe_password}"
    },
    "hairpin_addressing": {
        "value": "1"
    },
    "hostname": {
        "value": "${dns_hostname}.${dns_zonename}"
    },
    "pg_dbname": {
        "value": "${pg_dbname}"
    },
    "pg_netloc": {
        "value": "${pg_address}"
    },
    "pg_password": {
        "value": "${rds_password}"
    },
    "pg_user": {
        "value": "postgres"
    },
    "placement": {
        "value": "placement_s3"
    },
    "production_type": {
        "value": "external"
    },
    "s3_bucket": {
        "value": "${tfe_bucket}"
    },
    "s3_endpoint": {},
    "s3_region": {
        "value": "${region}"
    }
}
EOF


# replicated.conf file
cat > /etc/replicated.conf <<EOF
{
    "DaemonAuthenticationType":          "password",
    "DaemonAuthenticationPassword":      "${tfe_password}",
    "TlsBootstrapType":                  "server-path",
    "TlsBootstrapHostname":              "${dns_hostname}.${dns_zonename}",
    "TlsBootstrapCert":                  "/tmp/server.crt",
    "TlsBootstrapKey":                   "/tmp/server.key",
    "BypassPreflightChecks":             true,
    "ImportSettingsFrom":                "/tmp/tfe_settings.json",
    "LicenseFileLocation":               "/tmp/${filename_license}"
}
EOF

# Get the public IP of the instance
PUBLIC_IP=`curl http://169.254.169.254/latest/meta-data/public-ipv4`

pushd /var/tmp
curl -o install.sh https://install.terraform.io/ptfe/stable
bash ./install.sh no-proxy private-address=${tfe-private-ip} public-address=$PUBLIC_IP
