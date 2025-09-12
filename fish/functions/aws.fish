function aws --wraps=aws --description "AWS CLI with automatic paging and syntax highlighting"
    # Store original arguments before argparse modifies them
    set -l original_argv $argv

    # Parse known AWS CLI arguments we care about
    argparse --ignore-unknown 'output=' no-cli-pager -- $argv
    or return

    set -l output_format json
    set -l use_pager true
    set -l bat_lang json

    # Check if --no-cli-pager was specified (takes precedence)
    if set -q _flag_no_cli_pager
        set use_pager false
    end

    # Check if --output was specified
    if set -q _flag_output
        set output_format $_flag_output
    end

    # Determine pager usage and bat language based on output format
    # (only if --no-cli-pager wasn't specified)
    if test $use_pager = true
        switch $output_format
            case table
                set use_pager false
            case yaml yaml-stream
                set bat_lang yaml
            case text
                set bat_lang txt
            case json
                set bat_lang json
        end
    end

    if test $use_pager = true; and isatty stdout
        command aws $original_argv | bat --language=$bat_lang --style=plain
    else
        command aws $original_argv
    end
end