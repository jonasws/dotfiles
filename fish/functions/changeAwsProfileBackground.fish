function changeAwsProfileBackground -v AWS_PROFILE --description "Change terminal background based on AWS profile"
    # Skip background change if this is a one-off command
    if test $_one_off_aws_command = true
        return
    end

    if test -z $AWS_PROFILE
        printf "\033]111\007"
    else
        # Define colors for different AWS profiles
        switch "$AWS_PROFILE"
            case cnops-prod-admin
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case cnops-prod-developer
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case trafficinfo-prod--admin
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case cnops-prod-developer
                set bg_color "#412B2F" # **Ultra-dark desaturated red** (Aged Wine)
            case default '*'
                set bg_color "#1E1E2E" # Default Mocha background
        end

        # Emit ANSI escape sequence to set the background color
        printf "\033]11;%s\007" $bg_color
    end
end