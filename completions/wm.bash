#!/usr/bin/env bash
# Bash completion for wm (watchman)
# Install: eval "$(wm completions bash)"

_wm_completions() {
  local cur prev words
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Top-level commands
  local commands="setup schedule unschedule assets list remove run show retro logs completions"

  case "${COMP_CWORD}" in
    1)
      COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
      ;;
    2)
      case "${prev}" in
        remove)
          local tickers
          tickers=$(wm _complete_tickers 2>/dev/null)
          COMPREPLY=($(compgen -W "${tickers}" -- "${cur}"))
          ;;
        show)
          local tickers
          tickers=$(wm _complete_tickers 2>/dev/null)
          COMPREPLY=($(compgen -W "${tickers} --last -l" -- "${cur}"))
          ;;
        retro)
          COMPREPLY=($(compgen -W "--weekly --monthly -w -m list show" -- "${cur}"))
          ;;
        schedule)
          COMPREPLY=($(compgen -W "status" -- "${cur}"))
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
            ids=$(wm _complete_retro_ids 2>/dev/null)
            COMPREPLY=($(compgen -W "${ids}" -- "${cur}"))
          fi
          ;;
        remove)
          local tickers
          tickers=$(wm _complete_tickers 2>/dev/null)
          COMPREPLY=($(compgen -W "${tickers}" -- "${cur}"))
          ;;
        *)
          ;;
      esac
      ;;
  esac
}

complete -F _wm_completions wm
