
wizard_install_dot-files() {

  local root
  root="$(dirname "${BASH_SOURCE[0]}")"/..

  common::do ln -sf "${root}"/etc/config.fish  "$HOME"/.config/fish/config.fish
  common::do ln -sf "${root}"/etc/vimrc        "$HOME"/.vimrc
  common::do ln -sf "${root}"/etc/tmux.conf    "$HOME"/.tmux.conf
  common::do ln -sf "${root}"/etc/bashrc       "$HOME"/.bashrc
}

wizard_install_apt() {
  common::required_help "$1" "

  install distribution packages
  "
  case $PLATFORM in
    Linux)
      if which apt >/dev/null; then
        common::sudo apt install "$@"
      fi
      ;;
    *)
      common::error "Unsupported platform \"$PLATFORM\""
      ;;
  esac

  return $#
}

wizard_install_git() {

  common::optional_help "$1" "

  install the newest git version
  "
  common::sudo add-apt-repository ppa:git-core/ppa -y
  common::sudo apt-get update
  common::sudo apt-get install git -y
}

wizard_install_vnc() {

  common::optional_help "$1" "

  install xfce4 and start a VNC server. for droplets
  "
  common::sudo apt update
  common::sudo apt install xfce4 xfce4-goodies tightvncserver
  common::sudo vncserver
  common::sudo vncserver -kill :1
  cat > "$HOME"/.vnc/xstartup << EOF
#!/bin/bash
xrdb \$HOME/.Xresources
startxfce4 &
EOF
  common::do chmod +x "$HOME"/.vnc/xstartup
}

wizard_install_java() {

  common::optional_help "$1" "

  install the Oracle JDK
  "
  common::sudo add-apt-repository ppa:webupd8team/java
  common::sudo apt update
  common::sudo apt install oracle-java8-installer
}

wizard_install_shellcheck() {

  common::optional_help "$1" "

  download and install the latest shellcheck
  "
  common::do cd /tmp/
  common::do wget \
    'http://ftp.us.debian.org/debian/pool/main/s/shellcheck/shellcheck_0.4.6-1_i386.deb'
  common::sudo dpkg -i shellcheck_*.deb || true
  common::sudo apt-get install -f
  common::do cd -
}

wizard_install_lua() {

  common::optional_help "$1" "

  compile and install lua 5.3.3
  "

  # shellcheck disable=SC2076
  if [[ $(lua -v) =~ "Lua 5.3.3" ]]; then
    echo "Lua already installed"
    return
  fi

  echo "installing lua"
  common::do cd /tmp/

  common::do wget 'https://www.lua.org/ftp/lua-5.3.3.tar.gz'
  common::do tar zxvf lua-5.3.3.tar.gz
  common::do cd lua-5.3.3
  common::do make linux
  common::sudo make install

  common::do cd -
  echo "done"
}

wizard_install_docker() {

  common::optional_help "$1" "

  install the dependencies and kernel headers for docker-ce
  "
  common::do curl -fsSL 'https://download.docker.com/linux/ubuntu/gpg' \
    | sudo apt-key add -
  common::sudo add-apt-repository \
    "\"deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\""
  common::sudo apt-get update
  common::do apt-cache policy docker-ce
  common::sudo apt-get install -y docker-ce
}

