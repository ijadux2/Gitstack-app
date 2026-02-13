#!/bin/bash

# GitStack Native - Runner Script

export LUA_PATH="/home/jadu/.luarocks/share/lua/5.4/?.lua;/home/jadu/.luarocks/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua;./src/?.lua;./src/?/init.lua;./?.lua;;"
export LUA_CPATH="/home/jadu/.luarocks/lib/lua/5.4/?.so;/usr/lib/lua/5.4/?.so;/usr/lib/lua/5.4/lgi/?.so;;"
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-1
export GDK_BACKEND=x11

cd "$(dirname "$0")"

lua5.4 main.lua "$@"
