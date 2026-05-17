#compdef wm
# Zsh completion for wm (watchman)
# Install: eval "$(wm completions zsh)"

_WM_CACHE_DIR="${HOME}/.local/share/watchman/cache"

_wm() {
  local -a commands
  commands=(
    'setup:Interactive configuration wizard'
    'schedule:Set up daily automated runs'
    'unschedule:Remove scheduled runs'
    'assets:Register assets to track'
    'list:List tracked assets'
    'remove:Stop tracking an asset'
    'run:Run analysis for all tracked assets'
    'show:Show analyses'
    'retro:Generate or view retrospectives'
    'logs:View log file'
    'completions:Output shell completion script'
  )

  _arguments -C \
    '1:command:->command' \
    '*::arg:->args'

  case "$state" in
    command)
      _describe 'command' commands
      ;;
    args)
      case "${words[1]}" in
        remove)
          local -a tickers
          [[ -f "${_WM_CACHE_DIR}/tickers" ]] && tickers=(${(f)"$(cat "${_WM_CACHE_DIR}/tickers")"})
          _describe 'ticker' tickers
          ;;
        show)
          local -a tickers
          [[ -f "${_WM_CACHE_DIR}/tickers" ]] && tickers=(${(f)"$(cat "${_WM_CACHE_DIR}/tickers")"})
          _alternative \
            'tickers:ticker:(${tickers})' \
            'flags:flag:(--last -l)'
          ;;
        retro)
          local -a retro_cmds
          retro_cmds=(
            'list:List all retrospectives'
            'show:Show a specific retrospective'
            '-w:Generate weekly retrospective'
            '-m:Generate monthly retrospective'
            '--weekly:Generate weekly retrospective'
            '--monthly:Generate monthly retrospective'
          )
          if [[ "${words[2]}" == "show" ]]; then
            local -a ids
            [[ -f "${_WM_CACHE_DIR}/retro_ids" ]] && ids=(${(f)"$(cat "${_WM_CACHE_DIR}/retro_ids")"})
            _describe 'id' ids
          else
            _describe 'retro command' retro_cmds
          fi
          ;;
        schedule)
          _describe 'subcommand' '(status:Show\ schedule\ status)'
          ;;
        logs)
          _describe 'flag' '(-f:Follow\ in\ real-time -n:Show\ last\ N\ lines --follow:Follow --lines:Lines)'
          ;;
        completions)
          _describe 'shell' '(bash:Bash\ completion zsh:Zsh\ completion)'
          ;;
      esac
      ;;
  esac
}

_wm "$@"
