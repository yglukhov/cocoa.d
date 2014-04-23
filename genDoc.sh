#!/bin/sh

DOCROOT=$(dirname "$0")
rdmd "$DOCROOT/bootDoc/generate.d" "$DOCROOT/../source"
