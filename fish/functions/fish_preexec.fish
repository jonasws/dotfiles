function fish_preexec --on-event fish_preexec --description "Detect one-off AWS_PROFILE commands and prevent background changes"
    if string match -qr '^AWS_PROFILE=' $argv[1]
        set -g _one_off_aws_command true
    else
        set -g _one_off_aws_command false
    end
end