#!/bin/bash

# Log file for user data script
LOG_FILE="/var/log/user-data.log"

echo "User data script started" >> $LOG_FILE

# Ensure NGINX is installed
echo "Installing NGINX..." >> $LOG_FILE
yum install -y nginx >> $LOG_FILE 2>&1

# Create index.html
echo "Creating index.html..." >> $LOG_FILE
cat > /usr/share/nginx/html/index.html <<EOF
<h1>Hello, World</h1>
<p>DB address: ${db_address}</p>
<p>DB port: ${db_port}</p>
EOF

# Start the NGINX server
echo "Starting NGINX..." >> $LOG_FILE
systemctl enable nginx >> $LOG_FILE 2>&1
systemctl start nginx >> $LOG_FILE 2>&1

echo "User data script completed" >> $LOG_FILE
