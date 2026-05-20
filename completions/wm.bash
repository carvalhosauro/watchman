#!/usr/bin/env bash
# Bash completion for wm (watchman)
# Install: eval "$(wm completions bash)"

_WM_CACHE_DIR="${HOME}/.local/share/watchman/cache"

_wm_cached_tickers() {
  local cache="${_WM_CACHE_DIR}/tickers"
  if [[ -f "$cache" ]]; then
    cat "$cache"
  fi
}

_wm_cached_retro_ids() {
  local cache="${_WM_CACHE_DIR}/retro_ids"
  if [[ -f "$cache" ]]; then
    cat "$cache"
  fi
}

_wm_completions() {
  local cur prev words
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Top-level commands
  local commands="setup schedule unschedule assets list remove run show retro accuracy alerts logs completions update"

  case "${COMP_CWORD}" in
    1)
      COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
      ;;
    2)
      case "${prev}" in
        remove)
          local tickers
          tickers=$(_wm_cached_tickers)
          COMPREPLY=($(compgen -W "${tickers}" -- "${cur}"))
          ;;
        show)
          local tickers
          tickers=$(_wm_cached_tickers)
          COMPREPLY=($(compgen -W "${tickers} --last -l" -- "${cur}"))
          ;;
        retro)
          COMPREPLY=($(compgen -W "--weekly --monthly -w -m list show" -- "${cur}"))
          ;;
        alerts)
          COMPREPLY=($(compgen -W "test status" -- "${cur}"))
          ;;
        schedule)
          COMPREPLY=($(compgen -W "status" -- "${cur}"))
          ;;
        accuracy)
          COMPREPLY=($(compgen -W "--ticker -t --provider -p --days -d --since -s --include-neutral" -- "${cur}"))
          ;;
        logs)
          COMPREPLY=($(compgen -W "--follow -f --lines -n" -- "${cur}"))
          ;;
        completions)
          COMPREPLY=($(compgen -W "bash zsh" -- "${cur}"))
          ;;
        *)
          ;;
      esac
      ;;
    3)
      local cmd="${COMP_WORDS[1]}"
      case "${cmd}" in
        retro)
          if [[ "${prev}" == "show" ]]; then
            local ids
            ids=$(_wm_cached_retro_ids)
            COMPREPLY=($(compgen -W "${ids}" -- "${cur}"))
          fi
          ;;
        remove)
          local tickers
          tickers=$(_wm_cached_tickers)
          COMPREPLY=($(compgen -W "${tickers}" -- "${cur}"))
          ;;
        show)
          if [[ "${prev}" != "-l" && "${prev}" != "--last" ]]; then
            local tickers
            tickers=$(_wm_cached_tickers)
            COMPREPLY=($(compgen -W "${tickers} --last -l" -- "${cur}"))
          fi
          ;;
        *)
          ;;
      esac
      ;;
    *)
      local cmd="${COMP_WORDS[1]}"
      case "${cmd}" in
        remove)
          local tickers
          tickers=$(_wm_cached_tickers)
          COMPREPLY=($(compgen -W "${tickers}" -- "${cur}"))
          ;;
      esac
      ;;
  esac
}

complete -F _wm_completions wm
