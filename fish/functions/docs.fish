function docs --description "Read a web page as markdown in leaf: the server's own markdown if it has one, defuddle otherwise"
    argparse h/help -- $argv
    or return 2

    if set -q _flag_help; or test (count $argv) -ne 1
        echo "usage: docs <url>" >&2
        return 2
    end

    # Shared with the find-docs skill, which redirects it into a file to grep.
    ~/.claude/skills/find-docs/read-page.sh $argv[1]
end
