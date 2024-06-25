set -gx LC_ALL en_US.UTF-8
set -gx PATH ~/.cargo/bin /opt/homebrew/opt/grep/libexec/gnubin /opt/homebrew/opt/gnu-tar/libexec/gnubin ~/go/bin ~/.local/bin /opt/homebrew/bin $PATH

fish_config theme choose "Dracula Official"

function __fish_describe_command
end

function repo-name
    basename (git rev-parse --show-toplevel)

end
alias grt "cd (git rev-parse --show-toplevel)"

# To not slow down Emacs searching/projectile magic while on macOS
if not builtin status is-interactive
    exit
end

test -f $HOME/dotfiles/fish/local.fish; and source $HOME/dotfiles/fish/local.fish

starship init fish | source

functions --erase fish_starship_prompt
functions --copy fish_prompt fish_starship_prompt


function fish_prompt
    # Fun with flags
    fish_starship_prompt | perl -p -e "
        s/\(eu-west-1\)/ 🇮🇪 /;    \
        s/\(eu-central-1\)/ 🇩🇪 /; \
        s/\(eu-north-1\)/ 🇸🇪 /"
end

fzf_configure_bindings --directory=\cf --git_status=\eg --git_log=\el

set -g fish_key_bindings fish_hybrid_key_bindings

function fish_user_key_bindings
    bind \ec fzf_cd_directory
    bind -M insert \ec fzf_cd_directory
end


set fish_color_command yellow
set fish_color_autosuggestion white

set -gx EDITOR nvim
set fzf_directory_opts --bind "ctrl-o:execute($EDITOR {} &> /dev/tty)"


abbr -a - "cd -"
abbr -a gsma "git switch main"

alias reload-fish-config "source ~/.config/fish/config.fish; and echo \"Fish config reloaded 🐟 🚀\""
alias as-tree "command tree --fromfile"
alias bg batgrep

alias zp "zed-preview"

function browse-ssm-params
    aws ssm describe-parameter --output=json \
        | jq -r ".Parameters[].Name" \
        | fzf
end

function git-dir-or-pwd
    git rev-parse --show-toplevel 2>/dev/null; or pwd
end

set -gx BD_OPT insensitive

set -gx FZF_DEFAULT_COMMAND "fd --type f"
set -gx FZF_CTRL_T_COMMAND "fd --type f"
set -gx FZF_OPEN_COMMAND "fd --type f . \$dir"

set -gx FZF_ENABLE_OPEN_PREVIEW 1
set -gx FZF_LEGACY_KEYBINDINGS 0
set -gx FZF_COMPLETE 2

set -gx FZF_CTRL_T_OPTS "
  --preview 'bat -n --color=always {}'
"

set -gx FZF_ALT_C_OPTS "
   --preview 'eza -l --color=always {}'
"


set -gx EZA_COLORS "\
gu=37:\
sn=32:\
sb=32:\
da=34:\
ur=34:\
uw=35:\
ux=36:\
ue=36:\
gr=34:\
gw=35:\
gx=36:\
tr=34:\
tw=35:\
tx=36:"


set -gx RIPGREP_CONFIG_PATH $HOME/.ripgreprc

# Eza is cooler than ls, duh
alias ll "eza --long --icons"
alias l "eza --long --icons"
alias la "eza --long --all --icons"

alias tree "eza --tree --long"

abbr -a dc "docker compose"

# Calendar
alias month="gcal --starting-day=1"

# Tig aliases
abbr -a t tig
alias tst "tig status"

# Git alises
abbr -a gsm "git switch master"


abbr -a tf terraform


alias spin tspin

function lambdalogs
    awslogs groups -p /aws/lambda | grep -v suat | fzf -1 -d / --with-nth 4 \
        --bind "ctrl-w:execute(awslogs get {} ALL $argv --watch | tspin),enter:execute(awslogs get {} ALL $argv | tspin)+abort"
end

function test-one
    set testName (fd --type f -e java "" src/test | fzf | xargs -J {} basename {} .java)

    if test -n "$testName"
        commandline "mvn test -Dtest=$testName"
    end
end

function findpass
    set entry (op list items \
        | jq -r ".[] | [.uuid, .overview.url, .overview.title] | @tsv" \
        | fzf)

    set name (printf $entry | cut -f 3)
    set uuid (printf $entry | cut -f 1)

    op get item $uuid \
        | jq -r '.details.fields[] | select(.designation=="password").value' \
        | pbcopy

    echo "Copied password for entry" $name "to clipbaord"
end

# Runs npm start if possible
function s
    if test -f package.json
        if test -f yarn.lock
            echo yarn start $argv
            command yarn start $argv
        else if test -f (git rev-parse --show-toplevel)/pnpm-lock.yaml
            echo pnpm start $argv
            command pnpm start $argv
        else
            echo npm start $argv
            command npm start $argv
        end
    else
        echo "No package.json found"
    end
end

function up
    if test -f docker-compose.yml
        command docker-compose up $argv
    else
        echo "No docker-compose.yml found"
    end
end

zoxide init fish | source

alias fishconfig "nvim ~/dotfiles/fish/config.fish; and reload-fish-config"

alias lg lazygit

abbr -a gp!! "git push --force"


# Enable AWS CLI autocompletion: github.com/aws/aws-cli/issues/1079
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

set -g fzf_history_opts --with-nth="4.." --preview-window="down,30%,border-top,wrap"

function fzf_cd_directory --description "Change directory Replace the current token with the selected file paths."
    # Inspired by https://github.com/PatrickF1/fzf.fish/blob/main/functions/_fzf_search_directory.fish
    # Directly use fd binary to avoid output buffering delay caused by a fd alias, if any.
    # Debian-based distros install fd as fdfind and the fd package is something else, so
    # check for fdfind first. Fall back to "fd" for a clear error message.
    set -f fd_cmd (command -v fdfind || command -v fd  || echo "fd")
    set -f --append fd_cmd --color=always $fzf_fd_opts

    set -f fzf_arguments --select-1 --preview='eza --all --color=always {}' --ansi $fzf_directory_opts
    set -f token (commandline --current-token)
    # expand any variables or leading tilde (~) in the token
    set -f expanded_token (eval echo -- $token)
    # unescape token because it's already quoted so backslashes will mess up the path
    set -f unescaped_exp_token (string unescape -- $expanded_token)

    # If the current token is a directory and has a trailing slash,
    # then use it as fd's base directory.
    if string match --quiet -- "*/" $unescaped_exp_token && test -d "$unescaped_exp_token"
        set --append fd_cmd --base-directory=$unescaped_exp_token
        # use the directory name as fzf's prompt to indicate the search is limited to that directory
        set --prepend fzf_arguments --prompt="Change Directory $unescaped_exp_token> " --preview="_fzf_preview_file $expanded_token{}"
        set -f dir_path_selected $unescaped_exp_token($fd_cmd --type d 2>/dev/null | _fzf_wrapper $fzf_arguments)
    else
        set --prepend fzf_arguments --prompt="Change Directory> " --query="$unescaped_exp_token" --preview='_fzf_preview_file {}'
        set -f dir_path_selected ($fd_cmd --type d 2>/dev/null | _fzf_wrapper $fzf_arguments)
    end


    if test $status -eq 0
        cd (string escape -- $dir_path_selected | string join ' ')
    end

    commandline --function repaint
end

function gradlew
    set -l current_dir (pwd)

    while true
        # Check if 'gradlew' exists in the current directory
        if test -x "$current_dir/gradlew"
            # 'gradlew' found, print the path and exit
            echo "Using gradlew in $current_dir"
            pushd $current_dir
            command ./gradlew $argv
            # If you're feeling really brave, switch out for the line below to use 8GB of max heap
            # command ./gradlew $argv -Dorg.gradle.jvmargs="-Xmx8g"
            set -l gradleExitCode $status
            popd
            return $gradleExitCode

        else if [ "$current_dir" = / ]
            # Reached the root directory, stop
            echo "No 'gradlew' found in any parent directory."
            return 1
        end

        # Move up to the parent directory
        set current_dir (dirname $current_dir)
    end
end

function urlescape
    if isatty stdin
        string replace -a / %2F $argv
    else
        cat | string replace -a / %2F $argv
    end
end

function get-easytoken
    set -l env $argv[1]
    set -l user $argv[2]

    set -l functionName  $env-tokenproxy-easytoken-get
    set -l profileName si-$env

    set -l payload (jq -n --arg user $user '{user: $user } | @base64')
    set -l responseOutputFile (mktemp)
    aws lambda invoke \
        --function-name $functionName \
        --invocation-type RequestResponse \
        --output json \
        --profile $profileName \
        --payload $payload  \
        $responseOutputFile &> /dev/null

    if test $status -eq 0
        jq -r .data.accessToken $responseOutputFile
    end
    rm $responseOutputFile
end

function introspect_raw
    set -l token $argv[1]
    http --ignore-stdin --form https://api.uat.ciam.tech-03.net/as/introspect.oauth2 token=$token
end

function introspect
    introspect_raw $argv \
        | yq --input-format json '
      .scope |= split(" ")
    | .exp |= (from_unix | format_datetime("15:04:05")) 
    | .iat |= (from_unix | format_datetime("15:04:05")) 
    '
end


function view-mr-pipeline
    set -l projectPath (urlescape (git remote -v | perl -ln -E 'say /\/([\w-\/\.]+)\.git/' | uniq | grep -v "Jonas.Stromsodd"))
    set -l branch (urlescape (__git.current_branch))
    set -l mrId (glab api projects/$projectPath/merge_requests\?source_branch=$branch | jq -r ".[0].iid")
    set -l sha (glab api projects/$projectPath/merge_requests/$mrId/pipelines | jq -r ".[0].sha")
    glab pipeline view $sha $argv
end

function start-my-day
    echo "Good morning!"

    echo "Updating your brew"
    brew update; and brew upgrade

    echo "Update fisher plugins"
    fisher update

    echo "Updating wezterm"
    brew upgrade --cask wezterm@nightly --no-quarantine --greedy-latest

    echo "Updating your lazy.nvim plugins"
    nvim --headless "+Lazy! sync" +qa
    echo

    echo "Updating intellimacs"
    git -C ~/.intellimacs pull --rebase
end


function nittedal
    set -l query '
query GetDepartures {
  stopPlace(id: "NSR:StopPlace:337") {
    estimatedCalls(whiteListed: {
            lines: ["GJB:Line:R30", "GJB:Line:L3"]
    }) {
      expectedDepartureTime
      situations {
      	summary {
      	  language
          value
        }
      }
      serviceJourney {
        line {
          publicCode
        }
      }
      destinationDisplay {
        frontText
      }
      quay {
        publicCode
      }
    }
  }
}
  '

    http --ignore-stdin POST https://api.entur.io/journey-planner/v3/graphql query=$query "ET-Client-Name: jonas-laptop-cli" \
        | jq -r '
            .data.stopPlace.estimatedCalls[] 
            | [.expectedDepartureTime, .destinationDisplay.frontText, .quay.publicCode, .serviceJourney.line.publicCode, .situations[0].summary[0].value]
            | @tsv' \
        # Only show the time, including display Norwegian characters
        | perl -Mutf8 -CS -ne 'print "\e[34m$2\e[0m\t\e[96m$3\e[0m\t\e[92m$4\e[0m\t\e[95m$5\e[0m\t\e[93m$6\e[0m\n"
              if /(\d{4}-\d{2}-\d{2}T)(\d{2}:\d{2}):\d{2}\+\d{2}:\d{2}\t(\p{L}+)\t(\d+)\t(.+)\t(.*)/' \
        | column -t -s (echo -n \t)
end

function xray-traceid
    set -l traceId $argv[1]
    if test -z $traceId
        set -a traceId (uuidgen | string lower)
    end
    printf 'Root=1-%x-%s' (date +%s) (string replace -a "-" "" $traceId)
end

set -gx DOCKER_HOST "unix://$HOME/.colima/default/docker.sock"
set -gx DOCKER_DEFAULT_PLATFORM linux/amd64
set -gx DOCKER_HIDE_LEGACY_COMMANDS 1

# Use fnm
# NOTE: Try to keep  this at the bottom of  the file, to ensure fnm appears at "front" of the PATH variable
fnm env --use-on-cd --corepack-enabled | source
direnv hook fish | source

set -gx LESSOPEN "|/opt/homebrew/Cellar/bat-extras/2024.02.12/bin/batpipe %s"
set -e LESSCLOSE

# The following will enable colors when using batpipe with less:
set -gx LESS -XFRi
set -gx BATPIPE color
set -gx FX_THEME 1
set -gx FX_SHOW_SIZE true
set -gx BATDIFF_USE_DELTA true

alias man batman

set -gx GLAMOUR_STYLE dracula
set -gx PAGER less
set -gx AWS_PAGER "bat --plain --language json"
set -gx AWS_DEFAULT_OUTPUT json

# tabtab source for packages
# uninstall by removing these lines
[ -f ~/.config/tabtab/fish/__tabtab.fish ]; and . ~/.config/tabtab/fish/__tabtab.fish; or true

source ~/.config/op/plugins.sh
