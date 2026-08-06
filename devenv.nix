{ pkgs, lib, config, inputs, ... }:

{
  # General-purpose dev tooling: act runs GitHub Actions locally (via docker),
  # jq for general JSON munging.
  packages = [ pkgs.act pkgs.jq ];
}
