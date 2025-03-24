{
  description = "jonasws Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
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
          security.pam.services.sudo_local.touchIdAuth = true;

          nixpkgs.config = {
            allowUnfree = true;
            allowUnsupportedSystem = false;
          };
          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = with pkgs; [
            fish
            nixfmt-rfc-style
          ];

          homebrew = {
            enable = true;
            onActivation = {
              upgrade = true;
            };
            casks = [
              "nordvpn"
              "slack"
              "rectangle"
              "raycast"
              "karabiner-elements"
            ];
            brews = [
              "pngpaste"
              "docker"
              "docker-compose"
              "docker-buildx"
              "nushell"
              "starship"
              # "lnav"
              "mise"
              "fnm"
              "ymtdzzz/tap/otel-tui"
              "pkg-config"
              "cairo"
              "pango"
              "libpng"
              "jpeg"
              "lnav"
              "tailspin"
              "giflib"
              "bat"
              "bat-extras"
              "librsvg"
            ];
          };

          nix.package = pkgs.nix;
          nix.channel.enable = false;

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          programs.fish.enable = false;
          # environment.shells = [ pkgs.fish ];
          users.users.jonasws = {
            home = "/Users/jonasws";
            # shell = pkgs.fish;
          };

          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 6;

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
          home-manager.darwinModules.home-manager
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
    };
}
