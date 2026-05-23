# td.zsh-theme - cyberpunk prompt for Termux and proot-distro

autoload -Uz colors && colors
autoload -Uz vcs_info
setopt complete_aliases
setopt PROMPT_SUBST

zstyle ':vcs_info:git:*' formats ' %F{213}[ %F{45} %b %F{213}]%f'
zstyle ':vcs_info:git:*' actionformats ' %F{213}[ %F{45} %b|%a %F{213}]%f'
precmd() { vcs_info }

exit_status='%(?..%K{52}%F{255} ERR %? %f%k)'

PROMPT_SYMBOL='%K{17}%F{51} λ %f%k'
PROMPT_DIVIDER='%F{213}◈%f'

if [[ -n "$PREFIX" && "$PREFIX" == */com.termux/* ]]; then
    user_name="Ryo"
else
    user_name="$(whoami)"
fi

user_host='%B%F{45}[ %F{51}'"$user_name"' %F{39}%m %F{45}]%f'
dir_display='%B%F{39}[ %F{228}%~ %F{39}]%f'

PROMPT='
%B%F{45}┌─%f $user_host $PROMPT_DIVIDER $dir_display${vcs_info_msg_0_}
%B%F{213}└─%f${PROMPT_SYMBOL} '

RPROMPT="$exit_status"
