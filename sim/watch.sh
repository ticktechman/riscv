#!/usr/bin/env bash
###############################################################################
##
##       filename: watch.sh
##    description:
##        created: 2026/05/25
##         author: ticktechman
##
###############################################################################

# fswatch -o minisoc.sv | xargs -n1 -I {} make mini.run
fswatch -o hawks.sv | xargs -n1 -I {} make hawks

###############################################################################
