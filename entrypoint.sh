#!/bin/sh
/lt-server --address=127.0.0.1 --port=8080 --secure=true "$@" &
nginx -g 'daemon off;'