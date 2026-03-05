function build-screen --description "Watch CNOPS build screen for specified environment" -a env_name -a interval
    # Validate required environment argument
    if test -z "$env_name"
        echo "Error: Environment is required. Usage: build-screen <env> [interval]"
        echo "Available environments: dev, staging, prod"
        return 1
    end

    # Set default interval
    if test -z "$interval"
        set interval 15
    end

    # Validate environment
    if not contains $env_name dev staging prod
        echo "Error: Environment must be one of: dev, staging, prod"
        return 1
    end

    # Validate interval is a number
    if not string match -qr '^\d+$' $interval
        echo "Error: Interval must be a positive integer"
        return 1
    end

    echo "🚀 Starting build screen for $env_name environment (refresh every $interval seconds)"
    echo "Press Ctrl+C to stop"

    hwatch -n $interval --no-title --no-summary --mouse --color "FORCE_COLOR=1 nu ~/overlays/build-screen.nu $env_name"
end