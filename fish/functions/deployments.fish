function deployments --description "Show deployments for environment using nu shell"
    # Forwards all args to the nu command. Supports:
    #   deployments prod            (prefix defaults to cnops)
    #   deployments cnops prod
    #   deployments cn-cx prod
    nu -l -c "deployments $argv"
end
