#!/bin/sh
# SUDO_ASKPASS helper for the Settings update agent. sudo passes its prompt as
# the first argument; kdialog prints the entered password to stdout.
exec kdialog --password "${1:-Administrator password required}"
