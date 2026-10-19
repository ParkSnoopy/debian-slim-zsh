#compdef init.sh

_init_sh() {
	local curcontext="$curcontext" state line
	typeset -A opt_args

	local -a topics
	topics=(
		'git-config:Configure Git with delta and LFS'
		'golang:Install Go toolchain'
		'oh-my-tmux:Install Oh My Tmux configuration'
		'oh-my-zsh:Install Oh My Zsh'
		'python-uv:Install Python 3, uv, and ruff'
		'python-tldr:Install tldr client'
		'nanorc:Install syntax highlighting for Nano'
		'podman:Install Podman, podman-compose, and sudo defaults for nested containers'
		'sparky-extras:Enable the Sparky core repository'
		'display-clients:Install Wayland and X11 client libraries'
		'rust:Install stable Rust with the complete profile without PATH changes'
		'backports:Enable opt-in Debian 13 backports'
		'\*:All available topics'
	)

	local -a subcommands
	subcommands=(
		'install:Install only selected topics'
		'update:Compare commit hash and replace ~/init.sh if newer'
	)

	local -a common_opts
	common_opts=(
		'(-h --help)'{-h,--help}'[Show help]'
		'--list[Print available topics]'
		'--dry-run[Preview core install commands only]'
		'-y[Skip confirmation prompt]'
	)

	_arguments -s \
		$common_opts \
		'*--exclude[Remove topics after selection]:topic:->topics' \
		':command:->cmds' \
		'*:topic:->topics' && return 0

	case "$state" in
		cmds)
			_describe -t commands 'command' subcommands
			;;
		topics)
			_describe -t topics 'topic' topics
			;;
	esac
}

_init_sh "$@"
