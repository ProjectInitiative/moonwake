{
  description = "A flake for the moonwake.io website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Use pnpm for faster, more efficient installs
        nodeDeps = pkgs.pnpm.buildPnpmProject {
          name = "moonwake-node-deps";
          src = ./.;
          pnpmLockFile = ./pnpm-lock.yaml;
          # This hash will need to be updated after you run `pnpm i` inside the shell
          # The command to get the new hash will be in the error message.
          pnpmLockHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };

        # The Astro build command
        astroBuild = pkgs.runCommand "moonwake-dist" {
          src = ./.;
          nativeBuildInputs = [ pkgs.nodejs_22 pkgs.pnpm ];
        } ''
          # pnpm needs a home directory
          export HOME=$(mktemp -d)
          
          # Copy source and deps
          cp -r $src/. .
          chmod -R u+w .
          ln -s ${nodeDeps}/node_modules ./node_modules

          # Run the build
          ./node_modules/.bin/pnpm run build

          # Copy the output to $out
          cp -r ./dist $out
        '';

      in
      {
        # Development Shell: `nix develop`
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nodejs_22
            pkgs.pnpm
          ];
          shellHook = ''
            echo "Welcome to the Moonwake dev environment!"
            echo "Run 'pnpm install' if you changed dependencies."
            echo "Run 'pnpm dev' to start the dev server."
          '';
        };

        # The final build artifact: a Docker/OCI container image
        # Build with: `nix build .#image`
        packages.image = pkgs.dockerTools.buildImage {
          name = "moonwake-io"; # This will be the image name
          tag = "latest";

          # Use a minimal Nginx image from nixpkgs as the base
          contents = [ pkgs.nginx ];
          
          # Copy our built website and the nginx config into the image
          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ astroBuild ]; # The 'dist' directory
            pathsToLink = [ "/usr/share/nginx/html" ]; # Link dist to nginx's webroot
          };

          # Configure the container
          config = {
            Cmd = [ "${pkgs.nginx}/bin/nginx" "-g" "daemon off;" ];
            ExposedPorts = { "80/tcp" = {}; };
          };
        };

        defaultPackage = self.packages.${system}.image;

      });
}
