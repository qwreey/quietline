#!/bin/zsh

reset=$'\e[0m'
bold=$'\e[1m'
faint=$'\e[2m';     no_faint_bold=$'\e[22m'
italic=$'\e[3m';    no_italic=$'\e[23m'
underline=$'\e[4m'; no_underline=$'\e[24m'
invert=$'\e[7m';    no_invert=$'\e[27m'

# --------------------------------------------

# TODO: stopwatch
# TODO: exit code
# TODO: gitstatusd
# TODO: venv
# TODO: node version
# TODO: java home version <<?

# custom function here

# layout
QTM_HOSTNAME_OVERRIDE="" # If you have same hostname pcs a lot, you can add nickname for classify each other
QTM_TOPLINE="▁"
QTM_PROMPT="%{%F{238}%}▍%{%F{064}%}%(#.#.%(!.!.$))%{%f%} "
QTM_PROMPT_QUOTE="%{%F{238}%}▍%{%F{064}%}…%{%f%} "
QTM_LAYOUT_BASE="%s{$reset%}%i{%F{246}%}%l{%F{239}%}"
QTM_LAYOUT=(
	# ---- Extension methods ----
	# %t{ content %}  : topbar slot, good for previous process informations
	#                 : The topbar slot is not affected by shared styles
	# %e{ content %}  : execute command then show result in runtime.
	#                 : if execution fail, ignore errored layout
	# %+e{ content %} : similar to %e, but it allows output contains another extension
	#                 : methods. slower than regular %e
	# %s{ content %}  : shared content for line row and info row, for styling.
	#                   inner content will not be counted as displaying charactor
	# %l{ content %}  : similar to %s, line only content for styling
	# %i{ content %}  : similar to %s, info only content for styling
	# %!w             : disable wc, use $# to calculate size of string may inaccurate
	#                 : if content contains full-width charactor, but very fast
	# %+w             : enable wc, default enabled
	# You can check all colors by using spectrum_ls
	EXITCODE  "%t{ %F{202}err! %e{qtheme-exitcode%}$reset%}"
	EXITMEAN  "%t{ %F{196}(%e{qtheme-exitmeaning%})$reset%}"
	STOPWATCH "%t{ %F{226}%e{qtheme-stopwatch%} taken$reset%}"

	HEAD     "%!w%i{%F{238}%}▍"
	SSH      "%!w %i{%F{148}%}%e{qtheme-ssh%}"

	USERNAME "%!w %i{%F{196}%}%l{%F{160}%}%e{qtheme-username%}"
	DELIMIT  "%!w %i{$bold%}@"
	HOSTNAME "%!w %i{%F{214}%}%l{%F{172}%}%e{qtheme-hostname%}"
	DELIMIT  "%!w %i{$bold%}: "
	PATH     "%l{%F{63}%}%i{$bold%F{69}%}%e{print -rP '%~'%}"
	GIT      "%!w %i{$bold%}[%i{$reset%F{191}%}%l{%F{190}%}%+e{qtheme-git%}$QTM_LAYOUT_BASE%i{$bold%}]"

	TAIL     "%!w "
)

QTM_PROCESS_INFO_HEAD="%F{220}→$reset"
QTM_STOPWATCH_THRESHOLD="10" # seconds, minimum delay for stopwatch displaying

# exit codes
QTM_EXITCODE_ZERO="hide" # show | hide

QTM_OVERWRITE='off' # on | off

# --------------------------------------------

# -- Functions

qtheme-ssh() {
	if [[ -z "$SSH_TTY$SSH_CONNECTION$SSH_CLIENT" ]]; then
		return 1
	fi
	print -n "=>"
}

qtheme-username() {
	if [[ ! -z "$QTM_USERNAME_OVERRIDE" ]]; then
		print -n "$QTM_USERNAME_OVERRIDE"
	else
		print -n "$USER"
	fi
}

QTM_HOSTNAME_CACHE=''
qtheme-hostname() {
	if [[ ! -z "$QTM_HOSTNAME_OVERRIDE" ]]; then
		print -n "$QTM_HOSTNAME_OVERRIDE"
	elif [[ ! -z "$HOST" ]]; then
		print -n "$HOST"
	elif [[ ! -z "$QTM_HOSTNAME_CACHE" ]]; then
		print -n "$QTM_HOSTNAME_CACHE"
	elif which hostname &> /dev/null; then
		QTM_HOSTNAME_CACHE="$(hostname -s)"
		print -n "$QTM_HOSTNAME_CACHE"
	elif which hostnamectl &> /dev/null; then
		QTM_HOSTNAME_CACHE="$(hostnamectl --transient)"
		print -n "$QTM_HOSTNAME_CACHE"
	fi
}

qtheme-git-branch() {
	local ref
	ref=$(git symbolic-ref --quiet HEAD 2> /dev/null)
	local err=$?
	if [[ $err == 0 ]]; then
		print -n ${ref#refs/heads/} # remove "refs/heads/" to get branch
	else # not on a branch
		[[ $err == 128 ]] && return 1 # not a git repo
		ref=$(git rev-parse --short HEAD 2> /dev/null) || return 1
		print -n "${ref}" # hash prefixed to distingush from branch
	fi
}

qtheme-git-branch-fast() {
	[[ -z $QTM_GITDIR ]] && return 1
	[[ ! -e $QTM_GITDIR/HEAD ]] && return 1
	local content="$(cat $QTM_GITDIR/HEAD)"
	if [[ "$content" = "ref: "* ]]; then
		print -n ${content#ref: refs/heads/}
	else
		print -n ${content[1,7]}
	fi
}

qtheme-git-status() {
	local -A counts=(
		'STAGED' 0 # staged changes
		'CHANGED' 0 # unstaged changes
		'UNTRACKED' 0 # untracked files
		'BEHIND' 0 # commits behind
		'AHEAD' 0 # commits ahead
		'DIVERGED' 0 # commits diverged
		'STASHED' 0 # stashed files
		'CONFLICTS' 0 # conflicted files
		'CLEAN' 1 # clean branch 1=true 0=false
	)

	# Retrieve status
	local raw lines
	raw="$(git -C "$QTM_GITDIR/../" status --porcelain -b 2> /dev/null)"
	if [[ $? == 128 ]]; then
		return 1 # catastrophic failure, abort
	fi
	lines=(${(@f)raw})

	# Process tracking line
	if [[ ${lines[1]} =~ '^## [^ ]+ \[(.*)\]' ]]; then
		local items=("${(@s/,/)match}")
		for item in $items; do
			if [[ $item =~ '(behind|ahead|diverged) ([0-9]+)?' ]]; then
				case $match[1] in
					'behind') counts[BEHIND]=$match[2];;
					'ahead') counts[AHEAD]=$match[2];;
					'diverged') counts[DIVERGED]=$match[2];;
				esac
			fi
		done
	fi

	# Process status lines
	for line in $lines; do
		if [[ $line =~ '^##|^!!' ]]; then
			continue
		elif [[ $line =~ '^U[ADU]|^[AD]U|^AA|^DD' ]]; then
			counts[CONFLICTS]=$(( ${counts[CONFLICTS]} + 1 ))
		elif [[ $line =~ '^\?\?' ]]; then
			counts[UNTRACKED]=$(( ${counts[UNTRACKED]} + 1 ))
		elif [[ $line =~ '^[MTADRC] ' ]]; then
			counts[STAGED]=$(( ${counts[STAGED]} + 1 ))
		elif [[ $line =~ '^[MTARC][MTD]' ]]; then
			counts[STAGED]=$(( ${counts[STAGED]} + 1 ))
			counts[CHANGED]=$(( ${counts[CHANGED]} + 1 ))
		elif [[ $line =~ '^ [MTADRC]' ]]; then
			counts[CHANGED]=$(( ${counts[CHANGED]} + 1 ))
		fi
	done

	# Check for stashes
	if $(headline-git rev-parse --verify refs/stash &> /dev/null); then
		counts[STASHED]=$(headline-git rev-list --walk-reflogs --count refs/stash 2> /dev/null)
	fi

	# Update clean flag
	for key val in ${(@kv)counts}; do
		[[ $key == 'CLEAN' ]] && continue
		(( $val > 0 )) && counts[CLEAN]=0
	done

	echo ${(@kv)counts} # key1 val1 key2 val2 ...
}

qtheme-git() {
	local branch="$(qtheme-git-branch-fast)"
	if [[ -z $branch ]]; then
		return 1
	fi
	print -n "$branch"
	local -A counts=( $(qtheme-git-status) )

	if [[ $counts[CLEAN] == 1 ]]; then
		return 0
	fi
	if [[ $counts[STAGED] != 0 ]]; then
		print -n " +${counts[STAGED]}"
	fi
	if [[ $counts[CHANGED] != 0 ]]; then
		print -n " !${counts[CHANGED]}"
	fi
	if [[ $counts[UNTRACKED] != 0 ]]; then
		print -n " ?${counts[UNTRACKED]}"
	fi
	if [[ $counts[BEHIND] != 0 ]]; then
		print -n " ↓${counts[BEHIND]}"
	fi
	if [[ $counts[AHEAD] != 0 ]]; then
		print -n " ↑${counts[AHEAD]}"
	fi
	if [[ $counts[STASHED] != 0 ]]; then
		print -n " *${counts[STASHED]}"
	fi
	if [[ $counts[CONFLICTS] != 0 ]]; then
		print -n " #${counts[CONFLICTS]}"
	fi
}

qtheme-stopwatch() {
	if [[ $QTM_CMD_TIME == 0 ]]; then
		return 1
	fi
	local curr=$(date +%s)
	if (( QTM_CMD_TIME + QTM_STOPWATCH_THRESHOLD <= curr )); then
		local diff=$(( curr - QTM_CMD_TIME ))
		local sec=$(( diff % 60 ))
		local min=$(( diff / 60 % 60 ))
		local hour=$(( diff / 60 / 60 ))
		if [[ $hour != 0 ]]; then
			print -n "${hour}h ${min}m ${sec}s"
		elif [[ $min != 0 ]]; then
			print -n "${min}m ${sec}s"
		elif [[ $sec != 0 ]]; then
			print -n "${sec}s"
		fi
	else
		return 1
	fi
}

# Guess the exit code meaning
qtheme-exitmeaning() { # (num)
	# Ref: https://tldp.org/LDP/abs/html/exitcodes.html
	# Ref: https://man7.org/linux/man-pages/man7/signal.7.html
	# Note: These meanings are not standardized
	case $QTM_ERR in
		126) print -n 'Command cannot execute';;
		127) print -n 'Command not found';;
		129) print -n 'Hangup';;
		130) print -n 'Interrupted';;
		131) print -n 'Quit';;
		132) print -n 'Illegal instruction';;
		133) print -n 'Trapped';;
		134) print -n 'Aborted';;
		135) print -n 'Bus error';;
		136) print -n 'Arithmetic error';;
		137) print -n 'Killed';;
		138) print -n 'User signal 1';;
		139) print -n 'Segmentation fault';;
		140) print -n 'User signal 2';;
		141) print -n 'Pipe error';;
		142) print -n 'Alarm';;
		143) print -n 'Terminated';;
		*) return 1 ;;
	esac
}

qtheme-exitcode() {
	if [[ $QTM_ERR == 0 && $QTM_EXITCODE_ZERO != "show" ]]; then
		return 1
	fi
	print -n "$QTM_ERR"
}

# -- Renderer

cursor_up=$'\e[1F'
cursor_show=$'\e[?25h'
cursor_hide=$'\e[?25l'
cursor_down=$'\e[1B'
cursor_colhome=$'\e[1G'

qtheme-get-width() {
	print -n "${$(print -n "$1" | wc -L -)% -}"
}

qtheme-findup-first() {
        local path_
        path_="${PWD}"
        if [ -e "${path_}/${1-}" ]; then
                printf "%s\n" "${path_}/${1-}"
		return 0
        fi
        while [ "${path_}" != "" ] && [ "${path_}" != '.' ]; do
                path_=${path_%/*}
                if [ -e "${path_}/${1-}" ]; then
                        printf "%s\n" "${path_}/${1-}"
			return 0
                fi
        done
	return 1
}

QTM_COMPILED=()
QTM_COMPIDX=-1
qtheme-compile() {
	local -a visible=( ${(@s::)1} )
	local -a braces=()
	local skip=0
	local region=''
	local in_exec=''

	for idx in {1..${#visible}}; do
		if (( $skip >= 1 )); then
			(( skip -= 1 ))
			continue
		fi
		local curr=${visible[$idx]}
		local mod=${visible[$(( $idx + 1 ))]}
		local next=${visible[$(( $idx + 2 ))]}
		local nnext=${visible[$(( $idx + 3 ))]}

		if [[ ( ! -z $in_exec ) && $curr == '%' && $mod == '}' ]]; then
			# detect end of execute
			QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]="$in_exec"
			QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]="$region"
			in_exec=''
			region=''
			skip=1
		elif [[ ! -z $in_exec ]]; then
			# process execute content
			region+="$curr"
		elif [[ $curr == '%' && $mod == 'e' && $next == '{' ]]; then
			# execute command
			skip=2
			in_exec='e'
		elif [[ $curr == '%' && $mod == '+' && $next == 'e' && $nnext == '{' ]]; then
			# execute command
			skip=3
			in_exec='E'
			# TODO: consider async for %E{%}
		elif [[ $curr == "%" && $mod == "!" && $next == "w" ]]; then
			# disable wc
			QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]='W'
			QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]=''
			skip=2
		elif [[ $curr == "%" && $mod == "+" && $next == "w" ]]; then
			# enable wc
			QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]='w'
			QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]=''
			skip=2
		elif [[ $curr == '%' && ($mod == 't' || $mod == 'i' || $mod == 'l' || $mod == 's') && $next == '{' ]]; then
			# push braces
			skip=2
			QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]="$mod"
			QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]=''
			braces+=$mod
		elif [[ $curr == '%' && $mod == '}' ]]; then
			# pop here
			skip=1
			QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]="${braces[-1]:u}"
			QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]=''
			shift -p braces
		else
			# text content
			if [[ ${QTM_COMPILED[$((QTM_COMPIDX))]} == '#' ]]; then
				# append to previous
				QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]+="$curr"
			else
				QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]='#'
				QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]="$curr"
			fi
		fi
	done

	# commit
	QTM_COMPILED[$(( QTM_COMPIDX += 2 ))]='c'
	QTM_COMPILED[$(( QTM_COMPIDX + 1 ))]=''

	[[ ! -z $QTM_DEBUG ]] && qtheme-compiled-show
}
qtheme-compiled-show() {
	for key val in "${(@kv)QTM_COMPILED}"; do
		print key: $key
		print val: $val
	done
}
for key val in "${(@kv)QTM_LAYOUT}"; do
	qtheme-compile "$QTM_LAYOUT_BASE$val"
done

# Pre cache 50 repeating toplines
QTM_TOPLINE_PRECACHE=()
for len in {1..50}; do
	local curr=''
	for idx in {1..$len}; do
		curr+="$QTM_TOPLINE"
	done
	QTM_TOPLINE_PRECACHE+="$curr"
done

# Assemble elements
qtheme-assemble() {
	local line=''
	local info=''
	local topi=''
	local linebuf=''
	local infobuf=''
	local topibuf=''
	local contentbuf=''
	local zone='' # s: share style, i, l
	local use_wc=1
	local jump_to_commit=0
	for key val in "${(@kv)QTM_COMPILED}"; do
		if [[ $jump_to_commit != 0 && $key != 'c' ]]; then
			continue
		fi
		local process_contentbuf=0
		local commit=0
		local prev_zone="$zone"
		local prev_use_wc=$use_wc
		local expending_exeres=''
		case "$key" in
			c) # Commit
				process_contentbuf=1
				commit=1
			;;
			'#') # Text content
				contentbuf+="$val"
			;;
			E) # TODO: Expending execution
				expending_exeres="$(eval "$val")"
				jump_to_commit=$?
				process_contentbuf=1
			;;
			e) # Execution
				contentbuf+="$(eval "$val")"
				jump_to_commit=$?
			;;
			t|i|l|s) # Zone token
				zone="$key"
				process_contentbuf=1
			;;
			T|I|L|S) # Zone end token
				zone=''
				process_contentbuf=1
			;;
			w)
				if (( use_wc == 0 )); then
					use_wc=1
					process_contentbuf=1
				fi
			;;
			W)
				if (( use_wc == 1 )); then
					use_wc=0
					process_contentbuf=1
				fi
			;;
		esac
		# Render content buffer to line/info buffer
		if (( process_contentbuf == 1 )) && [[ ! -z "$contentbuf" ]]; then
			if [[ "$prev_zone" == 't' ]]; then
				# Topbar
				topibuf+="$contentbuf"
			else
				# Line
				if [[ -z "$prev_zone" ]]; then
					# Render line
					local length=0
					if (( prev_use_wc == 1 )); then
						length=$(qtheme-get-width "$contentbuf")
					else
						length=${#contentbuf}
					fi
					if (( length <= 50 )); then
						linebuf+="${QTM_TOPLINE_PRECACHE[$length]}"
					else
						for i in {1..$length}; do
							linebuf+="$QTM_TOPLINE"
						done
					fi
				elif [[ "$prev_zone" != 'i' ]]; then
					# Render raw line (style)
					linebuf+="$contentbuf"
				fi
				# Info
				if [[ "$prev_zone" != 'l' ]]; then
					# Render info
					infobuf+="$contentbuf"
				fi
			fi
			contentbuf=''
		fi
		# Commit to real line and info
		if (( commit == 1 )); then
			if (( jump_to_commit != 0 )); then
				jump_to_commit=0
			else
				line+="$linebuf"
				info+="$infobuf"
				topi+="$topibuf"
			fi
			linebuf=''
			infobuf=''
			topibuf=''
			zone=''
			use_wc=1
		fi
		# Expending execution
		if [[ ! -z $expending_exeres ]]; then
			linebuf+="$(qtheme-build-line "$expending_exeres")"
			infobuf+="$(qtheme-build-info "$expending_exeres")"
		fi
	done
	if [[ ! -z $topi ]]; then
		print -nP "\n$QTM_PROCESS_INFO_HEAD$topi$reset"
	fi
	print -nP "\n$line$reset"
	print -nP "\n$info\n"
}

qtheme-build-segment() {
	local -a visible=( ${(@s::)1} )
	local result=''
	local in_exec='f'
	local skip=0
	local buf_exec=''
	for idx in {1..${#visible}}; do
		if (( $skip >= 1 )); then
			(( skip -= 1 ))
			continue
		fi
		local curr=${visible[$idx]}
		local mod=${visible[$(( $idx + 1 ))]}
		local next=${visible[$(( $idx + 2 ))]}

		if [[ $in_exec == 'f' && $curr == '%' && $mod == 'e' && $next == '{' ]]; then
			in_exec='t'
			skip=2
		elif [[ $in_exec == 't' && $curr == '%' && $mod == '}' ]]; then
			result+="$(eval "$buf_exec")"
			if [[ "$?" != 0 ]]; then
				return 1
			fi
			buf_exec=''
			in_exec='f'
			skip=1
		elif [[ $in_exec == 't' ]]; then
			buf_exec+=$curr
		else
			result+=$curr
		fi
	done
	print -n "$result"
}

qtheme-build-info() {
	local -a visible=( ${(@s::)1} )
	local result=''
	local in_shared='f'
	local in_info='f'
	local in_line='f'
	local skip=0
	for idx in {1..${#visible}}; do
		if (( $skip >= 1 )); then
			(( skip -= 1 ))
			continue
		fi
		local curr=${visible[$idx]}
		local mod=${visible[$(( $idx + 1 ))]}
		local next=${visible[$(( $idx + 2 ))]}

		if [[ $curr == "%" && $mod == "!" && $next == "w" ]]; then
			skip=2
		elif [[ $curr == "%" && $mod == "+" && $next == "w" ]]; then
			skip=2
		elif [[ $curr == "%" && $mod == "}" && $in_shared == 't' ]]; then
			in_shared='f'
			skip=1
			result+='%}'
		elif [[ $curr == "%" && $mod == "}" && $in_info == 't' ]]; then
			in_info='f'
			skip=1
			result+='%}'
		elif [[ $curr == "%" && $mod == "}" && $in_line == 't' ]]; then
			in_line='f'
			skip=1
		elif [[ $in_info == 't' ]]; then
			result+=$curr
		elif [[ $in_shared == 't' ]]; then
			result+=$curr
		elif [[ $in_line == 't' ]]; then
		elif [[ $in_shared == 'f' && $curr == '%' && $mod == 's' && $next == '{' ]]; then
			in_shared='t'
			skip=2
			result+='%{'
		elif [[ $in_info == 'f' && $curr == '%' && $mod == 'i' && $next == '{' ]]; then
			in_info='t'
			skip=2
			result+='%{'
		elif [[ $in_line == 'f' && $curr == "%" && $mod == "l" && $next == "{" ]]; then
			in_line='t'
			skip=2
		else
			result+=$curr
		fi
	done
	print -n "$result"
}

qtheme-build-line() {
	local -a visible=( ${(@s::)1} )
	local result=''
	local in_shared='f'
	local in_info='f'
	local in_line='f'
	local skip=0
	local buf=''
	local use_wc='t'
	for idx in {1..${#visible}}; do
		if (( $skip >= 1 )); then
			(( skip -= 1 ))
			continue
		fi
		local curr=${visible[$idx]}
		local mod=${visible[$(( $idx + 1 ))]}
		local next=${visible[$(( $idx + 2 ))]}
		local process_buf='t'
		local brace_add=''

		if [[ $curr == "%" && $mod == "!" && $next == "w" ]]; then
			use_wc='f'
			skip=2
		elif [[ $curr == "%" && $mod == "+" && $next == "w" ]]; then
			use_wc='t'
			skip=2
		elif [[ $curr == "%" && $mod == "}" && $in_shared == 't' ]]; then
			in_shared='f'
			skip=1
			result+="%}"
			process_buf='f'
		elif [[ $curr == "%" && $mod == "}" && $in_info == 't' ]]; then
			in_info='f'
			skip=1
			process_buf='f'
		elif [[ $curr == "%" && $mod == "}" && $in_line == 't' ]]; then
			in_line='f'
			skip=1
			result+="%}"
			process_buf='f'
		elif [[ $in_info == 't' ]]; then
			process_buf='f'
		elif [[ $in_shared == 't' ]]; then
			result+=$curr
			process_buf='f'
		elif [[ $in_line == 't' ]]; then
			result+=$curr
			process_buf='f'
		elif [[ $in_shared == 'f' && $curr == '%' && $mod == 's' && $next == '{' ]]; then
			in_shared='t'
			skip=2
			brace_add='%{'
		elif [[ $in_info == 'f' && $curr == '%' && $mod == 'i' && $next == '{' ]]; then
			in_info='t'
			skip=2
		elif [[ $in_line == 'f' && $curr == "%" && $mod == "l" && $next == "{" ]]; then
			in_line='t'
			skip=2
			brace_add='%{'
		else
			buf+=$curr
			process_buf='f'
		fi

		if [[ $process_buf == 't' && ! -z $buf ]]; then
			for i in {1..$(qtheme-get-width $buf)}; do
				result+="$QTM_TOPLINE"
			done
			buf=""
		fi
		if [[ ! -z $brace_add ]]; then
			result+=$brace_add
		fi
	done
	if [[ ! -z $buf ]]; then
		for i in {1..$(qtheme-get-width $buf)}; do
			result+="$QTM_TOPLINE"
		done
	fi
	print -n "$result"
}

# -- Hooks

QTM_CMD_NUM=1
QTM_CMD_NUM_PREV=0
QTM_CMD_TIME=0
QTM_ERR="0"
QTM_GITDIR=''
add-zsh-hook preexec qtheme-preexec
qtheme-preexec() {
	(( QTM_CMD_NUM++ ))
	QTM_CMD_TIME=$(date +%s)
}

add-zsh-hook chpwd qtheme-chpwd
qtheme-chpwd() {
	QTM_GITDIR=$(qtheme-findup-first .git)
}
qtheme-chpwd

add-zsh-hook precmd qtheme-update-prompt
qtheme-update-prompt() {
	QTM_ERR="$?"
	if [[ $QTM_CMD_NUM == $QTM_CMD_NUM_PREV ]]; then
		QTM_ERR=0
	fi
	QTM_CMD_TIME=0

	# Old & Slow method
	# local segment=''
	# for key val in "${(@kv)QTM_LAYOUT}"; do
	# 	segment+="$QTM_LAYOUT_BASE"
	# 	segment+=$(qtheme-build-segment "$val")
	# done
        # local line="$(qtheme-build-line "$segment")"
        # local info="$(qtheme-build-info "$segment")"
	# print -rP "$line"
	# print -rP "$info"

	# Empty overwrite is unstable..
	if [[ $QTM_OVERWRITE == 'on' && $QTM_CMD_NUM == $QTM_CMD_NUM_PREV ]]; then
		print -nr "$cursor_hide$cursor_up$cursor_up$cursor_up$cursor_show"
	fi
	qtheme-assemble

	PROMPT="$QTM_PROMPT"
	PS2="$QTM_PROMPT_QUOTE"
	QTM_CMD_NUM_PREV=$QTM_CMD_NUM
}

