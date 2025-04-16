#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting MongoDB Sharded Cluster Setup..."

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to check if required ports are available
check_ports() {
    local ports=(27017 27018 27019 28017 28018 28019 8080 6379)
    for port in "${ports[@]}"; do
        if lsof -i ":$port" >/dev/null 2>&1; then
            echo "Port $port is already in use. Please free up this port and try again."
            exit 1
        fi
    done
}

# Function to cleanup existing containers
cleanup() {
    echo "Cleaning up existing containers..."
    docker-compose down -v >/dev/null 2>&1 || true
}

# Function to start the cluster
start_cluster() {
    echo "Starting MongoDB cluster..."
    docker-compose up -d
    echo "Waiting for containers to start..."
    sleep 10
}

# Function to wait for MongoDB to be ready
wait_for_mongodb() {
    echo "Waiting for MongoDB config servers to be ready..."
    until docker exec config1 mongosh --port 27019 --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
        echo "Waiting for config servers..."
        sleep 5
    done
    echo "Config servers are ready!"
}

# Function to initialize the config server replica set
initialize_config_servers() {
    echo "Initializing config server replica set..."
    docker exec config1 mongosh --port 27019 --eval '
        rs.initiate({
            _id: "configReplSet",
            configsvr: true,
            members: [
                {_id: 0, host: "config1:27019"},
                {_id: 1, host: "config2:27019"},
                {_id: 2, host: "config3:27019"}
            ]
        })
    '
    echo "Waiting for config replica set to initialize..."
    sleep 30
}

# Function to initialize shard replica sets
initialize_shards() {
    echo "Initializing shard1 replica set..."
    docker exec shard1 mongosh --port 27018 --eval '
        rs.initiate({
            _id: "shard1",
            members: [
                {_id: 0, host: "shard1:27018"},
                {_id: 1, host: "shard1_replica1:27020"},
                {_id: 2, host: "shard1_replica2:27021"}
            ]
        })
    '

    echo "Initializing shard2 replica set..."
    docker exec shard2 mongosh --port 27018 --eval '
        rs.initiate({
            _id: "shard2",
            members: [
                {_id: 0, host: "shard2:27018"},
                {_id: 1, host: "shard2_replica1:27022"},
                {_id: 2, host: "shard2_replica2:27023"}
            ]
        })
    '
    
    echo "Waiting for shard replica sets to initialize..."
    sleep 30
}

# Function to add shards to the cluster
add_shards() {
    echo "Adding shards to the cluster..."
    docker exec mongos1 mongosh --eval '
        sh.addShard("shard1/shard1:27018");
        sh.addShard("shard2/shard2:27018");
    '
    sleep 10
}

# Function to enable sharding and set up collections
setup_sharding() {
    echo "Setting up sharding for database and collections..."
    docker exec mongos1 mongosh --eval '
        sh.enableSharding("somedb");
        sh.shardCollection("somedb.users", { _id: "hashed" });
    '
    sleep 10
}

# Function to initialize data
initialize_data() {
    echo "Initializing data..."
    # Copy the initialization script to mongos1
    docker cp scripts/mongo-init.sh mongos1:/mongo-init.sh
    # Make it executable and run it
    docker exec mongos1 chmod +x /mongo-init.sh
    docker exec mongos1 /mongo-init.sh
}

# Function to verify the setup
verify_setup() {
    echo "Verifying setup..."
    # Check if all containers are running
    if [ "$(docker-compose ps --status running | wc -l)" -lt 8 ]; then
        echo "Error: Not all containers are running"
        exit 1
    fi

    # Check sharding status
    echo "Checking sharding status..."
    docker exec mongos1 mongosh --eval "sh.status()"
    
    # Verify MongoDB connection from API container
    echo "Verifying MongoDB connection from API..."
    docker exec pymongo_api python3 -c "
import motor.motor_asyncio
import asyncio
async def test_connection():
    client = motor.motor_asyncio.AsyncIOMotorClient('mongodb://mongos1,mongos2,mongos3')
    try:
        await client.admin.command('ping')
        print('MongoDB connection successful!')
    except Exception as e:
        print(f'MongoDB connection failed: {str(e)}')
        exit(1)
asyncio.run(test_connection())
"
}

# Main execution
echo "Starting MongoDB sharded cluster setup..."

check_docker
check_ports
cleanup
start_cluster
wait_for_mongodb
initialize_config_servers
initialize_shards
add_shards
setup_sharding
initialize_data
verify_setup

echo "Setup completed successfully!"
echo "MongoDB router is accessible at: mongodb://localhost:28017,localhost:28018,localhost:28019"
echo "API is accessible at: http://localhost:8080"

echo "✨ Setup complete! You can now access:"
echo "  - API: http://localhost:8080"
echo "  - MongoDB routers: localhost:28017, localhost:28018, localhost:28019"
echo "  - Config servers: localhost:27019"
echo "  - Shards: localhost:27018" 