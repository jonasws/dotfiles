function __fnox_after_dashdash \
        --description "True when the cursor is past fnox's `--` separator"
    # Whitespace on both sides is required, which is what keeps a profile named
    # `dev--admin` from looking like a separator. It also means a bare trailing
    # `--` (no space yet) still gets fnox's own flag completion: at that point
    # the token could still become `--help`.
    string match -qr -- '\s--\s' (commandline -cp)
end
