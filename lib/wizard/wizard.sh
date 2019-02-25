#!/bin/env bash

# wizard
#   The main wizard library. Functions are defined here, processed by
#   auto_cli.sh and built into a library sourced by bin/w
#
#   All the intermediary functions are produced by auto_cli.sh

wizard_switch() {

  local selection; selection="$(wizard show projects | fzf --cycle)"

  [[ $selection ]] || common::error "no selection made"
  wizard make session "$selection"
}

wizard_hunt() {

  common::optional-help "$1" "(-#) (pid or process name)

  find processes and send them a signal, default SIGTERM
  can signal multiple processes at once

    wizard hunt
    wizard hunt -9
    wizard hunt vim
    wizard hunt -HUP apache
  "

  local signal=-TERM
  case $1 in -*) signal="$1"; shift ;; esac

  ps ax \
    | { [[ $1 ]] && grep "$1"; cat; } \
    | cut -c 1-250 \
    | fzf --multi --cycle \
    | awk '{print $1}' \
    | xargs kill "$signal"
}

wizard_regenerate() {

  # safely tell the script to rewrite itself. running auto_wizard in the middle
  # of a wizard call will break the script (since it's overwriting itself)

  common::optional-help "$1" "

  regenerate wizard using auto_wizard, without clobbering ourselves
  "

  ( sleep .5
    auto_wizard | grep -v 'scripity'
  ) &

  disown
  exit 0
}


wizard_git_fetch() {

  common::optional-help "$1" "

  recursively discover git directories under the current working directory,
  fetch all branches
  "

  common::check-network || common::error "no network connection"

  while read -r directory; do
    (
      local dir; dir="$(dirname "$directory")"
      cd "$dir" || exit
      git fetch --quiet --all --recurse-submodules --prune
      echo "$dir"
    ) &

  done < <(find . -name .git) | sort
  wait
}


wizard_git_report() {

  common::optional-help "$1" "

  recursively discover git directories under the current working directory,
  print out a small human readable report on their status
  "

  while read -r directory; do
    (
      local dir; dir="$(dirname "$directory")"
      cd "$dir" || exit
      local status; status="$(git status)"

      grep -q 'Your branch is ahead of' <<< "$status" &&
        echo "$dir has local commits not pushed to remote"

      grep -q 'can be fast-forwarded' <<< "$status" &&
        echo "$dir can be fast-forwarded"

      grep -q 'Changes not staged for commit' <<< "$status" &&
        echo "$dir has uncommited, modified files"

      grep -q 'Untracked files' <<< "$status" &&
        echo "$dir has untracked files"

    ) &

  done < <(find . -name .git) | sort
  wait
}


common::require 'ffmpeg' &&
wizard_transcode_movies() {

  common::required-help "$1" "[file.avi ...]

  convert all input files to mp4 using ffmpeg, asks for confirmation before
  deleting the source file
  "

  local preset=veryslow

  echo "Processing: $*"
  for file in "$@"; do

    common::do ffmpeg -hide_banner -i "$file" \
      -c:v libx264 -crf 19 -preset "$preset" -strict -2 \
      -c:a aac -b:a 192k -ac 2 "${file%.*}.mp4" \
      || common::error "failed on \"$file\". Giving up"

    common::echo "Waiting..."; sleep 5
    common::do rm -i "$file"
  done
}


common::require 'service' 'ntpd' &&
wizard_sync_time() {

  common::optional-help "$1" "

  synchonrize the system clock with NTP
  "

  common::sudo service ntp stop
  common::sudo ntpd -gq
  common::sudo service ntp start
}


common::require 'xcape' &&
wizard_chromeos_swap-search-escape() {

  common::do xcape -e 'Super_L=Escape'
}


common::require 'dpkg' &&
wizard_show_largest-packages() {

  common::optional-help "$1" "

  list all packages installed, sorted by size

    $ w s lp | head -n 50
  "

  # shellcheck disable=SC2016
  dpkg-query -Wf '${Installed-Size}\t${Package}\n' \
    | sort -nr
}


wizard_start_http-server() {

  common::optional-help "$1" "(arguments)

  start an http server
  "

python3 -c "
from http.server import SimpleHTTPRequestHandler, test
import argparse

class InlineHandler(SimpleHTTPRequestHandler):

    def end_headers(self):
        mimetype = self.guess_type(self.path)
        is_file = not self.path.endswith('/')
        print(mimetype, is_file)

        # This part adds extra headers for some file types.
        if is_file and mimetype in ['text/plain', 'application/octet-stream']:
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Disposition', 'inline')
        super().end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bind', '-b', default='', metavar='ADDRESS',
                        help='Specify alternate bind address '
                             '[default: all interfaces]')
    parser.add_argument('port', action='store',
                        default=8000, type=int,
                        nargs='?',
                        help='Specify alternate port [default: 8000]')
    args = parser.parse_args()
    test(InlineHandler, port=args.port, bind=args.bind)
"
}


wizard_show_frequencies() {

  common::required-help "$1" "[amount]

  count the occurances of each input line
  "

  sort \
    | uniq -c \
    | sort -nr \
    | head -n "$1";
}


wizard_show_ratio() {

  common::required-help "$1" "[amount]

  count the occurances of each input line, produce ratio data
  "

  sort \
    | uniq -c \
    | sort -nr \
    | head -n "$1" \
    | awk '{a[$2]=$1;s+=$1}END{for(i in a)printf"%-55s%-15d%6.2f%%\n",i,a[i],a[i]/s*100}' \
    | sort -r -k 2,2 -n
}


wizard_parse_json() {

  common::optional-help "$1" "

  pipe in json and pretty print it

    $ curl remote.com/file.json | w parse json
  "

  python -m json.tool
}


wizard_parse_xml() {

  common::required-help "$1" "< file.xml

  pipe in a file an pretty print XML
  "

  xmllint --format -
}


wizard_update_platform() {
  # update everything, whatever that means

  case $PLATFORM in
    Linux)
      wizard update apt
      wizard update pip
      ;;
  esac
}

wizard_update_apt() {

  common::optional-help "$1" "

  update all apt packages
  "

  common::check-network || common::error "no network connection"

  common::sudo apt update
  common::sudo apt upgrade -y
  common::sudo apt-get autoremove -y
}


wizard_update_pip() {

  common::optional-help "$1" "

  update all python packages installed by pip
  "
  common::check-network || common::error "no network connection"

  sudo -H pip freeze --local \
    | grep -v '^\-e' \
    | cut -d = -f 1  \
    | xargs -n1 sudo -H python3 -m pip install -U
}


wizard_start_sshd() {

  common::optional-help "$1" "

  start sshd on Chrome OS
  "

  common::sudo mkdir -p -m0755 /var/run/sshd
  common::sudo /usr/sbin/sshd
}


# this is where we can inject code into the generated functions
#
# shellcheck disable=SC2034,SC2154,SC2016
{
meta_head[wizard_make_file]='
common::required-help "$1" "[language] [file name]
$__usage
"
'
meta_head[wizard_make_project]='
common::required-help "$1" "[language] [project name]
$__usage
"
'

meta_head[wizard]='
common::required-help "$1" "(-q | -s | -e)
$__usage
"

NUM_CPUS=$(getconf _NPROCESSORS_ONLN)
'

meta_body[wizard]='
-q|--quiet)  QUIET=1  ;;
-s|--silent) SILENT=1 ;;
-e|--echo)   ECHO=1 ;;
'
}
