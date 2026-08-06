{ pkgs, lib, config, inputs, ... }:

{
  # Test / CI tooling: act runs GitHub Actions locally (via docker),
  # jq is used by the package management scripts and their tests.
  packages = [ pkgs.act pkgs.jq ];

  languages.python = {
    enable = true;
    version = "3.12"; # Keep in sync with .python-version and pyproject.toml
    venv.enable = true;
    uv = {
      enable = true;
      sync = {
        enable = true;
        allGroups = true;             # Install all dependency groups
        # groups = [ "dev" "test" ];  # Or pick specific ones
        # extras = [ "plotting" ];    # Specific extras
        # allExtras = true;           # All extras
      };
    };
  };
}
