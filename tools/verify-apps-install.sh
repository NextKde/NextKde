#!/bin/sh
# Independent apps no longer form a fixed prefix bundle or own core services.
printf '%s\n' \
  'The monorepo application bundle verifier has been retired.' \
  'Inspect individual installer ownership/health instead:' \
  '  tools/kosctl install apps status --app calendar' \
  '  tools/kosctl install apps status --app calculator' \
  '  tools/kosctl install apps status --app weather' \
  '  tools/kosctl install apps status --app listenfree' \
  'Application runtime gates belong to the independent NextKde repositories.' >&2
exit 2
