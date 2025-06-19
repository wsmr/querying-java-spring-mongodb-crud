#!/bin/bash

# Diyawanna Spring Boot Deployment Script
# This script automates the build, upload, and restart process

# Configuration
PROJECT_DIR="/Users/sahan/Projects/_JAVA/@JAVA/querying-java-spring-mongodb-crud"
SSH_KEY="/Users/sahan/DEVELOPMENTS/SSH/Diyawanna_SSH_Key_Pair_2025_06_15.pem"
JAR_FILE="diyawanna-sup-backend-1.0.0.jar"
SERVER_IP="47.254.196.230"
SERVER_USER="root"
SERVICE_NAME="diyawanna-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        print_success "$1"
    else
        print_error "$2"
        exit 1
    fi
}

echo "=========================================="
echo "🚀 Diyawanna Deployment Script"
echo "=========================================="

# Step 1: Navigate to project directory and clean compile
print_status "Step 1: Navigating to project directory..."
cd "$PROJECT_DIR"
check_status "Changed to project directory" "Failed to navigate to project directory"

print_status "Step 2: Running Maven clean compile..."
mvn clean compile
check_status "Maven clean compile completed" "Maven clean compile failed"

# Step 3: Package the application
print_status "Step 3: Running Maven clean package..."
mvn clean package
check_status "Maven clean package completed" "Maven clean package failed"

# Step 4: Verify JAR file exists
print_status "Step 4: Verifying JAR file exists..."
if [ -f "target/$JAR_FILE" ]; then
    print_success "JAR file found: target/$JAR_FILE"
    # Show file size
    FILE_SIZE=$(ls -lh "target/$JAR_FILE" | awk '{print $5}')
    print_status "JAR file size: $FILE_SIZE"
else
    print_error "JAR file not found: target/$JAR_FILE"
    exit 1
fi

# Step 5: Upload JAR to server
print_status "Step 5: Uploading JAR file to server..."
scp -i "$SSH_KEY" "target/$JAR_FILE" "$SERVER_USER@$SERVER_IP:/root/"
check_status "JAR file uploaded successfully" "Failed to upload JAR file"

# Step 6: Connect to server and restart application
print_status "Step 6: Connecting to server and restarting application..."

# Create a temporary script to run on the server
TEMP_SCRIPT="/tmp/restart_app.sh"
cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/bash

SERVICE_NAME="diyawanna-app"
JAR_FILE="diyawanna-sup-backend-1.0.0.jar"

echo "🔄 Checking if systemd service exists..."
if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
    echo "✅ Service exists, stopping and restarting..."
    sudo systemctl stop "$SERVICE_NAME"
    sleep 2
    sudo systemctl start "$SERVICE_NAME"
    sleep 3
    
    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ Service restarted successfully"
        systemctl status "$SERVICE_NAME" --no-pager -l
    else
        echo "❌ Service failed to start, checking logs..."
        journalctl -u "$SERVICE_NAME" --no-pager -l -n 10
        exit 1
    fi
else
    echo "⚠️  Service doesn't exist, running JAR directly..."
    echo "🛑 Stopping any existing Java processes..."
    pkill -f "$JAR_FILE" || true
    sleep 2
    
    echo "🚀 Starting application in background..."
    # Set environment variables (you may need to adjust these)
    export SPRING_PROFILES_ACTIVE=prod
    nohup java -jar "/root/$JAR_FILE" > /root/app.log 2>&1 &
    
    sleep 5
    
    # Check if process is running
    if pgrep -f "$JAR_FILE" > /dev/null; then
        echo "✅ Application started successfully"
        echo "📋 Process info:"
        ps aux | grep "$JAR_FILE" | grep -v grep
        echo "📄 Last few log lines:"
        tail -n 5 /root/app.log
    else
        echo "❌ Application failed to start"
        echo "📄 Error logs:"
        cat /root/app.log
        exit 1
    fi
fi

echo "🔍 Checking if application is responding on port 8080..."
sleep 3
if curl -f -s http://localhost:8080/actuator/health > /dev/null 2>&1; then
    echo "✅ Application health check passed"
elif curl -f -s http://localhost:8080 > /dev/null 2>&1; then
    echo "✅ Application is responding on port 8080"
else
    echo "⚠️  Application may still be starting up or health endpoint not available"
    echo "🔍 Checking if port 8080 is listening..."
    if netstat -tlnp | grep :8080 > /dev/null 2>&1; then
        echo "✅ Port 8080 is listening"
    else
        echo "❌ Port 8080 is not listening"
        echo "📄 Recent logs:"
        if [ -f /root/app.log ]; then
            tail -n 10 /root/app.log
        else
            journalctl -u "$SERVICE_NAME" --no-pager -l -n 10
        fi
        exit 1
    fi
fi

echo "🎉 Deployment completed successfully!"
EOF

# Upload and execute the restart script
scp -i "$SSH_KEY" "$TEMP_SCRIPT" "$SERVER_USER@$SERVER_IP:/tmp/"
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" "chmod +x /tmp/restart_app.sh && /tmp/restart_app.sh"
check_status "Application restarted on server" "Failed to restart application on server"

# Clean up temporary script
rm "$TEMP_SCRIPT"

# Step 7: Final verification
print_status "Step 7: Final verification..."
print_status "Testing API endpoint..."

sleep 5
if curl -f -s "http://$SERVER_IP:8080" > /dev/null 2>&1; then
    print_success "✅ Application is accessible at http://$SERVER_IP:8080"
elif curl -f -s "http://$SERVER_IP:8080/actuator/health" > /dev/null 2>&1; then
    print_success "✅ Application health check passed at http://$SERVER_IP:8080/actuator/health"
else
    print_warning "⚠️  Application may still be starting up. Please check manually:"
    echo "   🌐 http://$SERVER_IP:8080"
    echo "   📊 http://$SERVER_IP:8080/actuator/health"
fi

echo ""
echo "=========================================="
print_success "🎉 Deployment Process Completed!"
echo "=========================================="
echo "📱 Application URL: http://$SERVER_IP:8080"
echo "🔍 Health Check: http://$SERVER_IP:8080/actuator/health"
echo "📋 To check logs: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP 'tail -f /root/app.log'"
echo "📋 To check service: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP 'systemctl status diyawanna-app'"
echo "=========================================="
