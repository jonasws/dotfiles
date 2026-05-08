function __rain_profile_from_cmdline
    set -l tokens (commandline -opc)
    set -l n (count $tokens)
    for i in (seq 1 $n)
        switch $tokens[$i]
            case -p --profile
                if test (math $i + 1) -le $n
                    echo $tokens[(math $i + 1)]
                    return 0
                end
            case '-p=*' '--profile=*'
                echo (string replace -r '^(-p|--profile)=' '' -- $tokens[$i])
                return 0
        end
    end
    return 1
end

function __rain_needs_stack
    __rain_profile_from_cmdline >/dev/null
    or return 1
    set -l tokens (commandline -opc)
    set -l stack_subs cat logs ls list rm watch
    set -l seen_sub ""
    set -l positional_count 0
    set -l skip_next 0
    set -l n (count $tokens)
    for i in (seq 2 $n)
        set -l t $tokens[$i]
        if test $skip_next -eq 1
            set skip_next 0
            continue
        end
        switch $t
            case -p --profile -r --region
                set skip_next 1
                continue
            case '-*'
                continue
        end
        if test -z "$seen_sub"
            if contains -- $t $stack_subs
                set seen_sub $t
            else
                return 1
            end
        else
            set positional_count (math $positional_count + 1)
        end
    end
    test -n "$seen_sub"; and test $positional_count -eq 0
end

function __rain_list_stacks
    set -l profile (__rain_profile_from_cmdline)
    or return 0
    aws cloudformation list-stacks --profile $profile \
        --query "StackSummaries[?StackStatus!='DELETE_COMPLETE'].StackName" \
        --output text 2>/dev/null | string split -- \t
end

complete -c rain -s p -l profile -x -a "(aws configure list-profiles 2>/dev/null)" -d "AWS profile"

complete -c rain -n __rain_needs_stack -f -a "(__rain_list_stacks)" -d Stack
