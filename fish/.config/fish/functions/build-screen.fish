function build-screen --description "Watch CNOPS build screen for specified environment" -a interval
    # Set default interval
    if test -z "$interval"
        set interval 15
    end

    # Validate interval is a number
    if not string match -qr '^\d+$' $interval
        echo "Error: Interval must be a positive integer"
        return 1
    end

    echo "🚀 Starting build screen (refresh every $interval seconds)"
    echo "Press Ctrl+C to stop"

    hwatch -n $interval --no-title --no-summary --mouse --color "FORCE_COLOR=1 nu ~/overlays/build-screen.nu"
end

