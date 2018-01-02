#!/bin/env bash


common::require 'dpkg' &&
wizard_clean_boot() {

  common::optional-help "$1" "

  safely cleans up old Linux kernel versions from /boot
  "

  dpkg --list \
    | grep linux-image \
    | awk '{ print $2 }' \
    | sort -V \
    | sed -n '/'"$(uname -r)"'/q;p' \
    | xargs sudo apt-get -y purge

  return $#
}


common::require 'dpkg' &&
wizard_clean_apt() {

  common::optional-help "$1" "

  force purge removed apt packages
  "

  dpkg --list \
    | grep "^rc" \
    | cut -d " " -f 3 \
    | xargs sudo dpkg --purge \
    || common::color-error "Looks like there's nothing to clean!"
}


wizard_clean_haskell() {

  common::do rm ./*.hi ./*.o || error "No files to clean"
  return 0
}


wizard_clean_files() {

  # clean up the filesystem under the current directory, mostly useful for
  # removing duplicate files insync creates

  local dry=0 counter=0

  common::optional-help "$1" "[--dry]

  smart remove duplicate file names and intermediary file types
  "

  local nargs=$#
  case $1 in -d|--dry) dry=1; shift; esac

  while read -r file; do
    local fixed; fixed="$(sed -e 's/[ ]*([0-9]\+)//' <<< "$file")"

    # make sure the file still exists
    if [[ -e "$file" ]] ; then

      # target file exists too, make sure they're different
      if [[ -f "$fixed" ]]; then

        soriginal=$(sha1sum "$file")
        snew=$(sha1sum "$fixed")

        echo "remove dup: $file"
        if [[ $soriginal != "$snew" ]]; then
          (( dry )) \
            || rm "$file" \
            || exit

        else
          echo "$file $fixed both exist but are different"
        fi

      else
        echo "rename dup: $file"
        (( dry )) \
          || mv "$file" "$fixed" \
          || exit
      fi

      (( counter++ ))
    fi
  done < <(find . -regex '.*([0-9]+).*')

  while read -r file; do
    echo "remove: $file"

    (( dry )) \
      || rm "$file" \
      || exit

    (( counter++ ))

  done < <(find . -regex '.*\.\(pyc\|class\|o\|bak\)')

  if (( dry )); then
    echo "Would have cleaned up $counter files"
  else
    echo "Cleaned up $counter files"
  fi

  return "$nargs"
}

