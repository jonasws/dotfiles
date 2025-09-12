function notify -a title body --description "Send terminal notification"
    printf "\e]777;notify;%s;%s\e\\" $title $body
end