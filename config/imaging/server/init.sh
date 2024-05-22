#!/bin/sh

cp /opt/imaging/config/sourcecode/* /opt/imaging/sourcecode/
cp /opt/imaging/config/nginx/conf/* /etc/nginx/
cp /opt/imaging/config/app-config.json /opt/imaging/imaging-service/
cp /opt/imaging/config/app.config /opt/imaging/imaging-service/


# get curl if not installed
if ! command -v curl &> /dev/null; then
    echo "curl is not installed. Installing..."
    apt-get update
    apt-get install -y curl
fi

_term() { 
    echo "Shutting down the server instance" 
    file_path="/opt/imaging/config/app.config"

    extract_value() {
        key="$1"
        grep "\"$key\"" "$file_path" | sed -E 's/.*"([^"]+)".*/\1/'
    }

   
    # Check if the file exists
    if [ -f "$file_path" ]; then
        eureka_host=$(extract_value "EUREKA_HOST")
        eureka_port=$(extract_value "EUREKA_PORT")
        appname=$(extract_value "SERVICE_NAME")
        hostname=$(extract_value "SERVICE_HOST")
        port=$(extract_value "PORT")
        
        if [ -n "$eureka_host" ]; then
            echo "Service Manager endpoint: $eureka_host"
        else
            echo "EUREKA_HOST not found in the file."
        fi

        if [ -n "$eureka_port" ]; then
            echo "eureka port: $eureka_port"
        else
            echo "eureka port not found in the file."
        fi
        if [ -n "$hostname" ]; then
            echo "hostname: $hostname"
        else
            echo "hostname not found in the file."
        fi
         if [ -n "$appname" ]; then
            echo "appname: $appname"
        else
            echo "appname not found in the file."
        fi
         if [ -n "$port" ]; then
            echo "port: $port"
        else
            echo "port not found in the file."
        fi
    else
        echo "File not found: $file_path"
    fi

    endpoint="http://$eureka_host:$eureka_port/eureka/apps/$appname/$hostname:$port"

    curl_result=$(curl -X DELETE -w '%{http_code}' $endpoint)

    if [ "$curl_result" == "200" ]; then
        echo "Server Un-registered from micro-service manager"
    else
        echo "Error sending DELETE request for $endpoint (HTTP Status: $curl_result)"
    fi
    echo "Shut down complete"
}

# handle termination and unregisteration to eureka
trap _term SIGTERM

echo "Starting Servers"
supervisord -c /etc/supervisor.conf --nodaemon &

child=$! 
wait "$child"