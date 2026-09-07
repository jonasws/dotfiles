function op-read-or-fail --description "Read 1Password secret references, failing if any read is denied or resolves empty"
    if test (count $argv) -eq 0
        echo "op-read-or-fail: no secret reference given" >&2
        return 2
    end

    if test (count $argv) -eq 1
        # Keep the value as a list of lines so multi-line secrets survive intact.
        set -l lines (op read -- $argv[1])
        or return 1

        # op exits 0 for a field that exists but holds nothing. That empty value is
        # what reaches the wrapped command as a bare flag when nothing checks for it.
        set -l joined (string join '' -- $lines)
        if test -z "$joined"
            echo "op-read-or-fail: $argv[1] resolved to an empty value" >&2
            return 1
        end

        printf '%s\n' $lines
        return 0
    end

    # One op process for every reference means one authorization prompt.
    set -l template
    for ref in $argv
        set -a template "{{ $ref }}"
    end

    set -l values (printf '%s\n' $template | op inject)
    or return 1

    # op inject emits one line per reference. Any other count means a secret
    # contained a newline, and values can no longer be matched to references.
    if test (count $values) -ne (count $argv)
        echo "op-read-or-fail: cannot read a multi-line secret alongside others" >&2
        return 1
    end

    for i in (seq (count $argv))
        if test -z "$values[$i]"
            echo "op-read-or-fail: $argv[$i] resolved to an empty value" >&2
            return 1
        end
    end

    printf '%s\n' $values
end
