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
QTM_TOPLINE="▁"
QTM_PROMPT="%{%F{240}%}▍%{%F{064}%}%(#.#.%(!.!.$))%{%f%} "
QTM_PROMPT_QUOTE="…"
QTM_LAYOUT_BASE="%s{$reset%}%i{%F{245}%}%l{%F{240}%}"
QTM_LAYOUT=(
    # %e{ content %} : execute command then show result in runtime, if execution fail, ignore errored layout
    # %s{ content %} : shared content for line row and info row, for styling.
    #                  inner content will not be counted as displaying charactor
    # %l{ content %} : similar to %s, line only content for styling
    # %i{ content %} : similar to %s, info only content for styling
    # You can check all colors by using spectrum_ls

    HEAD     "%i{%F{240}%}▍"
    SSH      " %e{qtheme-ssh%}"

    USERNAME " %i{%F{196}%}%l{%F{160}%}$USER"
    DELIMIT  " %i{$bold%}@ "
    HOSTNAME "%i{%F{214}%}%l{%F{172}%}%e{qtheme-hostname%}"
    DELIMIT  " %i{$bold%}: "
    PATH     "%l{%F{63}%}%i{$bold%F{69}%}%e{print -rP \"%~\"%}"
    BRANCH   " : %i{$bold%F{191}%}%l{%F{190}%}%e{qtheme-git-branch%}"

    TAIL     " "
)

QTM_LAST_PROCESS_INFO=(
    # only allows %e
    EXITCODE  " %F{202}err! %e{qtheme-exitcode%}$reset"
    EXITMEAN  " %F{196}(%e{qtheme-exitmeaning%})$reset"
    STOPWATCH " %F{226}%e{qtheme-stopwatch%} taken$reset"

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
    echo "%i{%F{148}%}=>"
}

qtheme-hostname() {
	if which hostnamectl &> /dev/null; then
		hostnamectl --transient
	else
		hostname -s
	fi
}

qtheme-git-branch() {
    local ref
    ref=$(git symbolic-ref --quiet HEAD 2> /dev/null)
    local err=$?
    if [[ $err == 0 ]]; then
        echo ${ref#refs/heads/} # remove "refs/heads/" to get branch
    else # not on a branch
        [[ $err == 128 ]] && return 1 # not a git repo
        ref=$(git rev-parse --short HEAD 2> /dev/null) || return 1
        echo ":${ref}" # hash prefixed to distingush from branch
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

qtheme-get-width() {
    print -n "${$(print -n "$1" | wc -L -)% -}"
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

        if [[ $curr == "%" && $mod == "}" && $in_shared == 't' ]]; then
            in_shared='f'
            skip=1
        elif [[ $curr == "%" && $mod == "}" && $in_info == 't' ]]; then
            in_info='f'
            skip=1
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
        elif [[ $in_info == 'f' && $curr == '%' && $mod == 'i' && $next == '{' ]]; then
            in_info='t'
            skip=2
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
    for idx in {1..${#visible}}; do
        if (( $skip >= 1 )); then
            (( skip -= 1 ))
            continue
        fi
        local curr=${visible[$idx]}
        local mod=${visible[$(( $idx + 1 ))]}
        local next=${visible[$(( $idx + 2 ))]}
        local process_buf='t'

        if [[ $curr == "%" && $mod == "}" && $in_shared == 't' ]]; then
            in_shared='f'
            skip=1
        elif [[ $curr == "%" && $mod == "}" && $in_info == 't' ]]; then
            in_info='f'
            skip=1
        elif [[ $curr == "%" && $mod == "}" && $in_line == 't' ]]; then
            in_line='f'
            skip=1
        elif [[ $in_info == 't' ]]; then
        elif [[ $in_shared == 't' ]]; then
            result+=$curr
            process_buf='f'
        elif [[ $in_line == 't' ]]; then
            result+=$curr
            process_buf='f'
        elif [[ $in_shared == 'f' && $curr == '%' && $mod == 's' && $next == '{' ]]; then
            in_shared='t'
            skip=2
        elif [[ $in_info == 'f' && $curr == '%' && $mod == 'i' && $next == '{' ]]; then
            in_info='t'
            skip=2
        elif [[ $in_line == 'f' && $curr == "%" && $mod == "l" && $next == "{" ]]; then
            in_line='t'
            skip=2
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

add-zsh-hook preexec qtheme-preexec
qtheme-preexec() {
    (( QTM_CMD_NUM++ ))
    QTM_CMD_TIME=$(date +%s)
}

add-zsh-hook precmd qtheme-update-prompt
qtheme-update-prompt() {
    QTM_ERR="$?"
    if [[ $QTM_CMD_NUM == $QTM_CMD_NUM_PREV ]]; then
        QTM_ERR=0
    fi
    local procsegment=''
    for key val in "${(@kv)QTM_LAST_PROCESS_INFO}"; do
        procsegment+="$(qtheme-build-segment "$val")"
    done
    QTM_CMD_TIME=0

    local segment=''
    for key val in "${(@kv)QTM_LAYOUT}"; do
        segment+="$QTM_LAYOUT_BASE"
        segment+=$(qtheme-build-segment "$val")
    done

    if [[ $QTM_OVERWRITE == 'on' && $QTM_CMD_NUM == $QTM_CMD_NUM_PREV ]]; then
        print -nr "$cursor_hide$cursor_up$cursor_up$cursor_up$cursor_show"
    fi
    if [[ ! -z "$procsegment" ]]; then
        print -rP "$QTM_PROCESS_INFO_HEAD$procsegment"
    fi
    local line="$(qtheme-build-line "$segment")"
    local info="$(qtheme-build-info "$segment")"
    if [[ -z $QTM_DEBUG ]]; then
        print -rP $line$reset
        print -rP $info
    else
        print $line$reset
        print $info
    fi
    PROMPT="$QTM_PROMPT"
    PS2="$QTM_PROMPT_QUOTE"
    QTM_CMD_NUM_PREV=$QTM_CMD_NUM
}


# source "$ZSHDIR/user-theme-headline/headline.zsh-theme"

