#!/bin/bash

# devbot
#
#   daemon to handle simple background tasks automatically based on a schedule
#
#   tasks are added to a schedule file, that's read every 5 seconds.
#     task :: interval time command ...
#
#   when a tasks time is reached, the command is run and it's added back to the
#   schedule with an updated time (current time + interval)
#
#   this approach makes devbot's schedule persist between runs, allowing very
#   infrequent tasks to be scheduled with confidence

# wizard commands

wizard_devbot_start() {

  common::optional-help "$1" "

  start devbot, will fail if already running
  "

  local pfile=~/.devbot-pid
  local lfile=~/.devbot-log

  [[ -e $pfile ]] && common::error "devbot already running"

  db::main 2>&1 >> $lfile &
  local pid=$!
  disown

  echo "$pid" > $pfile
}

wizard_devbot_add() {

  common::required-help "$2" "[interval] [command ...]

  add a new event to the devbot schedule

    w devbot add 60 'cd some/path/to/git/repo && git fetch'
  "

  local interval="$1"
  local procedure="${@:2}"

  db::add "$interval" "$procedure"

  return $#
}

wizard_devbot_kill() {

  common::optional-help "$1" "

  stop devbot, will fail if not running
  "

  local pfile=~/.devbot-pid

  [[ -e $pfile ]] || common::error "devbot is not running"

  pkill -F $pfile
  rm $pfile
}

wizard_devbot_status() {

  common::optional-help "$1" "

  report whether devbot is running, used by tmux status
  "

  local pfile=~/.devbot-pid

  if [[ -e $pfile ]]; then
    echo "✓"
  else
    echo "✗"
  fi
}


# devbot library

db::add() {

  # interval -> command ... -> none
  #
  # writes an event to the schedule at (now + interval)

  echo "add got $@"

  local schedule=~/.devbot-schedule
  local interval="$1"
  local procedure="$2"
  local when="$(expr $interval + $(date '+%s') )"

  echo "$interval $when $procedure" >> $schedule
}

db::initialize_events() {

  # none -> none
  #
  # add some basic tasks to the schedule

  local minute=60
  local fivem=300
  local hour=3600
  local day=86400

  db::add $fivem 'insync-headless reject_all_new_shares austin.voecks@gmail.com'

  db::add $hour 'cd $HOME && wizard git fetch'
  db::add $hour 'echo "" > ~/.devbot-log'

  db::add $day 'wizard update pip'
  db::add $day 'wizard update apt'

}

db::runner() {

  # interval -> unix epoch time -> command ... -> none
  #
  # check the time field of the input, if it's passed then run the command.
  # otherwise we add it back to schedule unchanged

  local data=( $@ )
  local schedule=~/.devbot-schedule

  local interval="${data[0]}"
  local when="${data[1]}"
  local procedure="${data[@]:2}"

  if (( when < $(date '+%s') )); then
    # run the event, add to schedule with updated time

    if [[ $procedure ]]; then
      eval "$procedure"
      db::add "$interval" "$procedure"

    else
      echo "runner error, no procedure"
    fi

  else
    # put the event back on the schedule unchanged
    echo "$interval $when $procedure" >> $schedule
  fi
}

db::main() {

  # none -> none
  #
  # set up the schedule if it's not already there, run the main event loop

  local schedule=~/.devbot-schedule
  local copy_schedule=~/.devbot-schedule-copy

  [[ -e $schedule ]] || db::initialize_events

  echo "starting devbot"
  while :; do

    # read the schedule from a copy, since we'll be rewriting the original
    touch "$schedule"
    mv $schedule $copy_schedule

    while read -r event; do

      db::runner "$event"
    done < $copy_schedule

    sleep 5
  done
}