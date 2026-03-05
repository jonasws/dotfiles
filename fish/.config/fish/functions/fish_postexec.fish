function fish_postexec --on-event fish_postexec --description "Reset one-off AWS command flag"
    set -g _one_off_aws_command false
end