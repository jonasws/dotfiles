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
    {
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
    }:
    let
      platform = "aarch64-darwin";
      systemName = "Jonass-MacBook-Pro";
      username = "jonasws";

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

          system.primaryUser = username;

          homebrew = {
            enable = true;
            global = {
              autoUpdate = false;
            };
            onActivation = {
              autoUpdate = false;
              upgrade = true;
              cleanup = "uninstall";
            };
            casks = [
              "nordvpn"
              "slack"
              "rectangle"
              "firefox@nightly"
              "wezterm@nightly"
              "spotify"
              "1password"
              "raycast"
              "karabiner-elements"
              "obsidian"
            ];
            brews = [
              "gping"
              "pngpaste"
              "docker"
              "docker-compose"
              "docker-buildx"
              "gcalcli"
              "icu4c"
              # "nushell"
              "starship"
              "lnav"
              "mise"
              "fnm"
              "ymtdzzz/tap/otel-tui"
              "pkg-config"
              "zlib"
              "gcc"
              "readline"
              "ossp-uuid"
              "libpq"
              "colima"
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
          nix.settings.download-buffer-size = 524288000;

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
          nixpkgs.hostPlatform = platform;
        };
    in
    {
      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;

      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#Jonass-MacBook-Pro
      darwinConfigurations."${systemName}" = nix-darwin.lib.darwinSystem {
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
      darwinPackages = self.darwinConfigurations."${systemName}".pkgs;
    };
}
