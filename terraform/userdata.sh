#!/bin/bash

# Fetch the public IP dynamically from the template
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

# debugging
echo "The public IP of this instance is: $PUBLIC_IP" > /home/ubuntu/public_ip.txt

echo "Copying the SSH Key to the server"
echo -e "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCSdhCmNC+wp+FnQS9HR6hDCjyDN+fO/D4GGJ92rkroaes/VR7U6erT4fNlLuIqgG5E4DiKr3yWrwRpooT7w+GYPhXvybaHw6q9bq3VwfbRF+PbVkmDCXEwXZ6sN0nTJCxsCRXs8QYjj3M35e4a0J+feYmkXvcwtY9ZznT6XYqytVju2nbpbdbx9dDI84Duf0zwkiZ/Yl9l77kKAhyY3r2IX8ssILxu9YnyE5/yUdz6jc8C2FdT6xzcd0I2qVJFdw3HhMjB5tnhBi6dGiBSkYxni3oGaM0v4qn25fRdOYRyHoSMGHugjHLySz73CUc7b5G1UdhmMolGNFPRR3MMio6OaxLl5rb4f3sZSqd47rzFE41Jyk51pCqOUiMVjLkWch7dinpBzzRrRznDWxqDrfijqKJLMc4OWfLMMPTydaqb3/qhGordxDw3iwQk+ub1pnB42uqzBC18ev1wp/FcKqo+7Ww7y0fuIjEOw+5P/M3rwQu6aAgH0xALxFjKdlNGrett+AUHq3I1OwywGz+unLz1mPLKn2iddt5qShUjVokhB9yCdGlILrpQgG2IDwxdA8dz7tVOV1ES9Ji7KY/q5exaeIS8taHhZeqF5wOKeoBb6qh6gjtw5B2pT98dm+Oe7wC9wp6G9DiHG47hqnQnLIH5bGXscMd0403fLCIKzx1vgw== dennm@Kомпухтатор"

# Update package manager
sudo apt-get update -y

# Install necessary packages
sudo apt-get install -y git golang postgresql postgresql-contrib nginx

# Clone the silly-demo application from GitHub
git clone https://github.com/shefeg/golang-demo /home/ubuntu/golang-demo

# Navigate to the application directory
cd /home/ubuntu/golang-demo

# Build the application
sudo GOOS=linux GOARCH=amd64 go build -o golang-demo
sudo chmod +x golang-demo

# Start PostgreSQL
sudo systemctl start postgresql
sudo -u postgres psql < db_schema.sql

# create a user
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'mynewpassword';" # error here
# psql -U tfdbuser -d db -h localhost


# Start the application with PostgreSQL connection info
DB_ENDPOINT=localhost DB_PORT=5432 DB_USER=postgres DB_PASS=mynewpassword DB_NAME=db ./golang-demo &

# Create Nginx configuration for silly-demo
cat <<EOF | sudo tee /etc/nginx/sites-available/silly-demo
server {
    listen 80;
    server_name $PUBLIC_IP;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Enable the site
sudo ln -s /etc/nginx/sites-available/silly-demo /etc/nginx/sites-enabled/

# Remove the default site
sudo rm /etc/nginx/sites-enabled/default

# Restart Nginx
sudo systemctl restart nginx
