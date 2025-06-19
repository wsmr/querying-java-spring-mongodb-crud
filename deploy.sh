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

# Function to wait for port to be available
wait_for_port() {
    local port=$1
    local timeout=${2:-120}  # Default 2 minutes timeout
    local counter=0
    
    echo "⏳ Waiting for port $port to be available (timeout: ${timeout}s)..."
    
    while [ $counter -lt $timeout ]; do
        if netstat -tlnp | grep ":$port " > /dev/null 2>&1; then
            echo "✅ Port $port is now listening"
            return 0
        fi
        
        sleep 2
        counter=$((counter + 2))
        
        # Show progress every 10 seconds
        if [ $((counter % 10)) -eq 0 ]; then
            echo "⏳ Still waiting... (${counter}s elapsed)"
        fi
    done
    
    echo "❌ Timeout waiting for port $port"
    return 1
}

# Function to show detailed logs
show_logs() {
    echo "📄 Application logs (last 20 lines):"
    echo "=================================="
    if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        journalctl -u "$SERVICE_NAME" --no-pager -l -n 20
    elif [ -f /root/app.log ]; then
        tail -n 20 /root/app.log
    else
        echo "No logs found"
    fi
    echo "=================================="
}

echo "🔄 Checking if systemd service exists..."
if systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
    echo "✅ Service exists, stopping and restarting..."
    sudo systemctl stop "$SERVICE_NAME"
    sleep 3
    
    # Show status before starting
    echo "📊 Service status before start:"
    systemctl status "$SERVICE_NAME" --no-pager -l || true
    
    sudo systemctl start "$SERVICE_NAME"
    sleep 5
    
    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ Service started successfully"
        systemctl status "$SERVICE_NAME" --no-pager -l
        
        # Wait for the application to fully start
        if wait_for_port 8080; then
            echo "✅ Application is fully started and listening on port 8080"
        else
            echo "❌ Application failed to start properly"
            show_logs
            exit 1
        fi
    else
        echo "❌ Service failed to start"
        show_logs
        exit 1
    fi
else
    echo "⚠️  Service doesn't exist, running JAR directly..."
    echo "🛑 Stopping any existing Java processes..."
    pkill -f "$JAR_FILE" || true
    sleep 3
    
    echo "🚀 Starting application in background..."
    # Set environment variables (you may need to adjust these)
    export SPRING_PROFILES_ACTIVE=prod
    nohup java -jar "/root/$JAR_FILE" > /root/app.log 2>&1 &
    
    sleep 5
    
    # Check if process is running
    if pgrep -f "$JAR_FILE" > /dev/null; then
        echo "✅ Application process started"
        echo "📋 Process info:"
        ps aux | grep "$JAR_FILE" | grep -v grep
        
        # Wait for the application to fully start
        if wait_for_port 8080; then
            echo "✅ Application is fully started and listening on port 8080"
        else
            echo "❌ Application failed to start properly"
            show_logs
            exit 1
        fi
    else
        echo "❌ Application failed to start"
        show_logs
        exit 1
    fi
fi

echo "🔍 Testing application endpoints..."

# Function to test endpoint with retries
test_endpoint() {
    local url=$1
    local description=$2
    local retries=3
    
    for i in $(seq 1 $retries); do
        echo "🔍 Testing $description (attempt $i/$retries)..."
        if curl -f -s -m 10 "$url" > /dev/null 2>&1; then
            echo "✅ $description is working"
            return 0
        fi
        
        if [ $i -lt $retries ]; then
            echo "⏳ Retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    echo "❌ $description failed after $retries attempts"
    return 1
}

# Test different endpoints
ENDPOINTS_TESTED=0
ENDPOINTS_WORKING=0

# Test root endpoint
if test_endpoint "http://localhost:8080" "Root endpoint"; then
    ENDPOINTS_WORKING=$((ENDPOINTS_WORKING + 1))
fi
ENDPOINTS_TESTED=$((ENDPOINTS_TESTED + 1))

# Test health endpoint
if test_endpoint "http://localhost:8080/actuator/health" "Health endpoint"; then
    ENDPOINTS_WORKING=$((ENDPOINTS_WORKING + 1))
fi
ENDPOINTS_TESTED=$((ENDPOINTS_TESTED + 1))

# Test API endpoint (adjust path as needed)
if test_endpoint "http://localhost:8080/api/v1/health" "API health endpoint"; then
    ENDPOINTS_WORKING=$((ENDPOINTS_WORKING + 1))
fi
ENDPOINTS_TESTED=$((ENDPOINTS_TESTED + 1))

echo "📊 Endpoint test results: $ENDPOINTS_WORKING/$ENDPOINTS_TESTED working"

if [ $ENDPOINTS_WORKING -gt 0 ]; then
    echo "🎉 Deployment completed successfully!"
    echo "🌐 Application is accessible and responding"
else
    echo "⚠️  Application is running but may have issues with endpoints"
    show_logs
    echo "🔍 Please check the application manually"
fi
EOF

# Upload and execute the restart script
scp -i "$SSH_KEY" "$TEMP_SCRIPT" "$SERVER_USER@$SERVER_IP:/tmp/"
ssh -i "$SSH_KEY" "$SERVER_USER@$SERVER_IP" "chmod +x /tmp/restart_app.sh && /tmp/restart_app.sh"

# Check the exit status of the remote script
REMOTE_EXIT_CODE=$?

# Clean up temporary script
rm "$TEMP_SCRIPT"

if [ $REMOTE_EXIT_CODE -eq 0 ]; then
    print_success "Application restarted successfully on server"
else
    print_error "Application restart encountered issues (exit code: $REMOTE_EXIT_CODE)"
    
    # Still continue with external verification
    print_status "Attempting external verification..."
fi

# Step 7: External verification
print_status "Step 7: External verification from local machine..."

sleep 10  # Give more time for the application to be ready

# Function to test external endpoint
test_external_endpoint() {
    local url=$1
    local description=$2
    
    print_status "Testing $description..."
    if curl -f -s -m 15 "$url" > /dev/null 2>&1; then
        print_success "✅ $description is accessible"
        return 0
    else
        print_warning "❌ $description is not accessible"
        return 1
    fi
}

EXTERNAL_SUCCESS=0

# Test different external endpoints
if test_external_endpoint "http://$SERVER_IP:8080" "Application root"; then
    EXTERNAL_SUCCESS=1
fi

if test_external_endpoint "http://$SERVER_IP:8080/actuator/health" "Health check"; then
    EXTERNAL_SUCCESS=1
fi

echo ""
echo "=========================================="
if [ $EXTERNAL_SUCCESS -eq 1 ]; then
    print_success "🎉 Deployment Process Completed Successfully!"
    echo "✅ Application is accessible from external network"
else
    print_warning "⚠️  Deployment Process Completed with Warnings"
    echo "🔍 Application may still be starting up or there might be network/firewall issues"
    echo "📋 Manual verification steps:"
    echo "   1. SSH to server: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP"
    echo "   2. Check service: systemctl status $SERVICE_NAME"
    echo "   3. Check logs: journalctl -u $SERVICE_NAME -f"
    echo "   4. Check port: netstat -tlnp | grep :8080"
    echo "   5. Test locally on server: curl http://localhost:8080"
fi
echo "=========================================="
echo "📱 Application URLs to test:"
echo "   🌐 http://$SERVER_IP:8080"
echo "   🏥 http://$SERVER_IP:8080/actuator/health"
echo ""
echo "📋 Useful commands:"
echo "   SSH: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP"
echo "   Logs: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP 'journalctl -u $SERVICE_NAME -f'"
echo "   Status: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP 'systemctl status $SERVICE_NAME'"
echo "   Stop: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP 'systemctl stop $SERVICE_NAME'"
echo "   Start: ssh -i $SSH_KEY $SERVER_USER@$SERVER_IP 'systemctl start $SERVICE_NAME'"
echo "=========================================="