
# Check for bash
[ -z "$BASH_VERSION" ] && return

################################################################################

__qorus_send() {
    local IFS=$'\n'
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(qorus-bash-completion-helper ${COMP_WORDS} ${COMP_WORDS[@]:0} $cur)"))
}

################################################################################

complete -o nospace -F __qorus_send ocmd
complete -o nospace -F __qorus_send ostart
complete -o nospace -F __qorus_send ostop
complete -o nospace -F __qorus_send oprop
complete -o nospace -F __qorus_send qrest
