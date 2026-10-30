# Fish completion for denv

set -l backends auto uv poetry pipenv pdm hatch conda pixi venv
set -l commands init status clean

# Global flags
complete -c denv -l no-color -d "Disable ANSI color output"
complete -c denv -s h -l help -d "Print help message"
complete -c denv -s v -l version -d "Print version information"

# Subcommands
complete -c denv -n "__fish_use_subcommand" -a init -d "Bootstrap workspace configuration (default)"
complete -c denv -n "__fish_use_subcommand" -a status -d "Show current workspace state"
complete -c denv -n "__fish_use_subcommand" -a clean -d "Remove denv configuration from workspace"

# init options (available with 'init' or without subcommands)
complete -c denv -n "__fish_seen_subcommand_from init; or not __fish_seen_subcommand_from $commands" -s b -l backend -x -a "$backends" -d "Environment backend"
complete -c denv -n "__fish_seen_subcommand_from init; or not __fish_seen_subcommand_from $commands" -s f -l force -d "Regenerate or update denv block in .envrc"
complete -c denv -n "__fish_seen_subcommand_from init; or not __fish_seen_subcommand_from $commands" -s n -l no-create -d "Do not create virtual environment if missing"
complete -c denv -n "__fish_seen_subcommand_from init; or not __fish_seen_subcommand_from $commands" -s g -l git-exclude -d "Hide .envrc and virtual environment in .git/info/exclude"
complete -c denv -n "__fish_seen_subcommand_from init; or not __fish_seen_subcommand_from $commands" -a "(__fish_complete_directories)" -d "Target workspace directory"

# status options
complete -c denv -n "__fish_seen_subcommand_from status" -s q -l quiet -d "Suppress output; exit 0 if configured, 1 otherwise"
complete -c denv -n "__fish_seen_subcommand_from status" -a "(__fish_complete_directories)" -d "Target workspace directory"

# clean options
complete -c denv -n "__fish_seen_subcommand_from clean" -a "(__fish_complete_directories)" -d "Target workspace directory"
