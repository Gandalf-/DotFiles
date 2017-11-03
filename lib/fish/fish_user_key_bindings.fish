
function fish_user_key_bindings
  bind \e. 'history-token-search-backward'
  bind \co 'history-search-forward'
  bind \cb 'commandline -i "bash -c \'";commandline -a "\'"'

  fish_default_key_bindings -M insert
  fish_vi_key_bindings insert

  bind -M insert \cf forward-char
  bind -M insert \ce end-of-line
  bind -M insert \ca beginning-of-line

  bind -M default E end-of-line
  bind -M default B beginning-of-line

  bind -M insert \ci fzf-file-widget
  bind -M insert \cr fzf-history-widget
  bind -M insert \ec fzf-cd-widget
  bind -M insert \eb cb
end