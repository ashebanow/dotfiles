# -----------------------------------------------------
# Shell aliases — command-name fixes and convenience shims
# -----------------------------------------------------

# zed-editor is packaged as `zeditor` in nixpkgs (avoids collision with
# the `zed` hex editor). Expose the expected `zed` name when it's present.
if command -v zeditor &> /dev/null; then
  alias zed=zeditor
fi
