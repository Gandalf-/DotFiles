# vim: set syntax=bash

# fish global settings
#===========================
set -gx __HOST__ (hostname       | sed 's/localhost/home/')
set -gx __HOST__ (echo $__HOST__ | sed 's/wkstn-avoecks.*/work/')

set -gx auto_proxy "http://proxy.west.isilon.com/proxy.pac"
set -gx EDITOR vim
set -gx XDG_CONFIG_HOME "$HOME"/.config/

# where are we?
test (hostname | head -c 13) = 'wkstn-avoecks'; and set at_work yes
test (whoami)   = 'chronos';       and set at_cros yes
set fish_version (fish --version | grep -o '[0-9]\+' | tr -d '\n')

# 'aliases'
function sfish; source ~/.config/fish/config.fish; end
function    ..; builtin cd ../;      command ls --color=auto ; end
function   ...; builtin cd ../../;   command ls --color=auto ; end
function  ....; builtin cd ../../../;command ls --color=auto ; end

# function preexec_test --on-event fish_preexec
#   _engine
# end

function postexec_test --on-event fish_postexec
  # _set_context 2>/dev/null
  _engine
end

# Location
#===========================

# workstation
if test "$at_work"
  set -gx DIFFDIR   ~/diffs/
  set -gx SCRIPITY  /mnt/ssd/
  set -gx ONEFSGIT  /mnt/ssd/onefs/
  set -gx DIMENSION work

  set PATH      ~/scripity-scripts/bin $PATH
  set wiki_loc  ~/wiki/index.md
  set scripts   ~/DotFiles

# chrome os native
else if test "$at_cros"
  set -gx PAGER /usr/local/bin/less
  set -gx TERM  screen
  set -gx DIMENSION cros

  set scripts   /usr/local/home/DotFiles
  set wiki_loc  /usr/local/home/google_drive/personal/wiki/index.md

# gallium
else if test -d ~/Documents/DotFiles
  set -gx DIMENSION gallium

  set scripts   ~/Documents/DotFiles
  set wiki_loc  ~/google_drive/personal/wiki/index.md

# birch, chroot
else if test -d ~/DotFiles
  set wiki_loc ~/wiki/index.md
  set scripts  ~/DotFiles

  set -gx DIMENSION ubuntu

# raspberry pi
else if test (whoami) = pi
  set scripts   ~/DotFiles

  set -gx DIMENSION raspberry

# temporary
else
  set -gx DIMENSION unknown
end

# Languages
#===========================

# rust
test -d ~/.cargo/bin/
  and set PATH ~/.cargo/bin/ $PATH

# haskell
test -d ~/.local/bin/
  and set PATH ~/.local/bin/ $PATH

test -d ~/.cabal/bin/
  and set PATH ~/.cabal/bin/ $PATH

# go
if test -d /usr/local/go/bin
  set PATH $HOME/google_drive/code/go/bin /usr/local/go/bin $PATH

  set -x -U GOPATH $HOME/google_drive/code/go
end

# Other executables
#===========================

set -gx TMP /tmp

# fzf
if test -e ~/.vim/bundle/fzf.vim/bin/fzf
  set PATH ~/.vim/bundle/fzf.vim/bin $PATH

else if test -e ~/.vim/bundle/fzf/bin/fzf
  set PATH ~/.vim/bundle/fzf/bin $PATH
end

set -gx FZF_DEFAULT_COMMAND 'ag -g ""'
set -gx FZF_DEFAULT_OPTS '--height 50% --border --cycle'

# autojump
test -f ~/.autojump/share/autojump/autojump.fish
  and . ~/.autojump/share/autojump/autojump.fish

# DotFiles scripts
if test "$scripts"
  set PATH $scripts/bin $PATH
  set -x PYTHONPATH $scripts/lib/python
  set -x PYTHONSTARTUP $scripts/etc/pythonrc
end

# vimwiki
if test "$wiki_loc"
  function vws; v "$wiki_loc" +"VimwikiSearch $argv"; end
  function vw ; cd (dirname "$wiki_loc"); vim "$wiki_loc"; end
end

# Fish git prompt and colors
#===========================
set __fish_git_prompt_showupstream 'yes'
set __fish_git_prompt_color_branch yellow

if test "$at_work"
  set -gx DISPLAY ':0'

else
  set __fish_git_prompt_showdirtystate 'yes'
  set __fish_git_prompt_showstashstate 'yes'
  set __fish_git_prompt_showuntrackedfiles 'no'
  set __fish_git_prompt_color_upstream_ahead green
  set __fish_git_prompt_color_upstream_behind red
  set __fish_git_prompt_color_upstream_ahead green
  set __fish_git_prompt_color_upstream_behind red
end

# Status Chars
set __fish_git_prompt_char_dirtystate 'd'
set __fish_git_prompt_char_stagedstate 'p'
set __fish_git_prompt_char_untrackedfiles 'n'
set __fish_git_prompt_char_stashstate 's'
set __fish_git_prompt_char_upstream_ahead '+'
set __fish_git_prompt_char_upstream_behind '-'

# colorful man pages
set -x LESS_TERMCAP_mb (printf "\033[01;31m")
set -x LESS_TERMCAP_md (printf "\033[01;31m")
set -x LESS_TERMCAP_me (printf "\033[0m")
set -x LESS_TERMCAP_se (printf "\033[0m")
set -x LESS_TERMCAP_so (printf "\033[01;44;33m")
set -x LESS_TERMCAP_ue (printf "\033[0m")
set -x LESS_TERMCAP_us (printf "\033[01;32m")
