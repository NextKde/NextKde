#!/bin/sh
# SDK ownership moved with the independent application; never mutate core here.
printf '%s\n' \
  'ListenFree SDK preparation moved to https://github.com/NextKde/ListenFree.' \
  'Use that repository and its build guide for a custom SDK build.' \
  'For a stable source Release: tools/kosctl install apps --app listenfree' >&2
exit 2
