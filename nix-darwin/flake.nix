{
  description = "jonasws Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      configuration =
        { pkgs, ... }:
        {
          security.pam.enableSudoTouchIdAuth =  true;

          nixpkgs.config = {
            allowUnfree = true;
            allowUnsupportedSystem = false;
          };
          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = with pkgs; [
            docker-client
            docker-buildx
            docker-compose
          ];

          homebrew = {
            enable = true;
            casks = [
              "slack"
              "rectangle"
              "raycast"
              "karabiner-elements"
              "firefox@nightly"
              "wezterm@nightly"
            ];
            brews = [
              "mise"
              "fnm"
              "ymtdzzz/tap/otel-tui"
              "pkg-config"
              "cairo"
              "pango"
              "libpng"
              "jpeg"
              "giflib"
              "superfile"
              "librsvg"
            ];
          };


          # Auto upgrade nix package and the daemon service.
          services.nix-daemon.enable = true;
          nix.package = pkgs.nix;
          nix.channel.enable = true;

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          programs.fish.enable = true;
          environment.shells = [ pkgs.fish ];
          users.users.jonasws = {
            home = "/Users/jonasws";
            shell = pkgs.fish;
          };

          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 5;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = "aarch64-darwin";
        };
    in
    {
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;

      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#Jonass-MacBook-Pro
      darwinConfigurations."Jonass-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          home-manager.darwinModule
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.jonasws = import ./home.nix;
            };
          }
        ];
      };

      # Expose the package set, including overlays, for convenience.
      darwinPackages = self.darwinConfigurations."Jonass-MacBook-Pro".pkgs;

      devShell.${system} = pkgs.mkShell {
        buildInputs = [
          pkgs.fish # Install Fish shell
        ];

        shellHook = ''
          fish -l  # Switch to Fish shell when entering the shell
        '';
      };
    };
}
