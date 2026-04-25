#!/usr/bin/env bash

systemctl --user stop graphical-session.target
systemctl --user stop graphical-session-pre.target

sleep 0.5

hyprctl dispatch exit

