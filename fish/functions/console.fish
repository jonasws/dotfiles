function console -a profile destination --description "Open AWS console with firefox container"
    set -l color (aws configure get color --profile $profile)
    set -l service $destination
    if test -z $service
        set service ecs/v2
    end
    set -l loginUrl (rain console --profile $profile --service $service --url)
    firefox-container --$color --name $profile $loginUrl
end