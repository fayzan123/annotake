# dmgbuild's layout for Annotake's disk image (scripts/release.sh):
#   dmgbuild -s scripts/dmg-settings.py -D app=<Annotake.app> -D icon=<AppIcon.icns> \
#     -D background=<dmg-background.tiff> Annotake <out.dmg>
# The window shows the app at the left and an Applications link at the right, over a background whose arrow
# says to drag one onto the other.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

window_rect = ((200, 120), (600, 400))
icon_size = 128
text_size = 13
icon_locations = {app_name: (150, 190), "Applications": (450, 190)}
show_icon_preview = False

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
