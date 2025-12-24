{
  description = "Development environment for the website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core website building
            zola
          ];

          shellHook = ''
            echo "🚀 Nexum website development environment"
            echo ""
            echo "Available commands:"
            echo "  zola serve    - Serve locally with hot reload"
            echo "  zola build    - Build the site"
            echo "  zola check    - Check for errors"
            echo "  treefmt       - Format all files"
            echo ""
            echo "Website URL: https://nxm.rs"
            echo "Local dev:   http://127.0.0.1:1111"
          '';
        };

        # Build package
        packages.default = pkgs.stdenv.mkDerivation {
          name = "nexum-website";
          src = ./.;

          buildInputs = [ pkgs.zola ];

          buildPhase = ''
            zola build
          '';

          installPhase = ''
            cp -r public $out
          '';
        };
      });
}
