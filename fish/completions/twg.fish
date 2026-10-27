function __twg_completion
  set -l words (commandline -opc)
  set -l current (commandline -ct)
  twg __complete -- $words $current
end
complete -c twg -f -a '(__twg_completion)'
