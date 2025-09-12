function deployments -a envName --description "Show deployments for environment using nu shell"
    nu -l -c "deployments $envName"
end