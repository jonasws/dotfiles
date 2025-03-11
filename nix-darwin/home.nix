# home.nix

{ config, pkgs, ... }:
{

  # Home Manager needs a bit of information about you and the paths it should
  # manage.

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # Docker stuff
    lazydocker

    # fastfetch

    # difftastic
    grc
    doggo
    btop
    yazi
    # spotify-player

    wget
    tree-sitter

    pre-commit
    carapace
    # open-policy-agent
    # regal

    # csvlens
    glow

    neovim
    git
    coreutils
    openssl

    # bat
    # bat-extras.batman
    # httpie
    xh
    hurl
    zoxide
    zellij
    # starship
    # go
    curl
    fd
    jq
    yq-go
    fx
    ripgrep
    # TODO: Enable after https://github.com/NixOS/nixpkgs/pull/385327 is merged
    # tailspin
    vivid
    rm-improved
    eza
    fzf

    gh
    glab
    delta
    # tig
    lazygit

    awslogs
    awscli2
    ssm-session-manager-plugin


    gradle
    _1password-cli
    # lnav
    ranger

    ookla-speedtest
    moreutils

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    ".wezterm.lua" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/wezterm/wezterm.lua";
    };


    ".ripgreprc" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/ripgrep/.ripgreprc";
    };
  };

    xdg.configFile = {
      neovim = {
        source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/lazyvim";
        target = "nvim";
        recursive = true;
      };
    };

  # You can also manage environment variables but you will have to manually
  # source
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/davish/etc/profile.d/hm-session-vars.sh
  #
  # if you don't want to manage your shell through Home Manager.
  home.sessionVariables = {
    # EDITOR = "emacs";
  };


  # Let Home Manager install and manage itself.
  programs = {
    home-manager.enable = true;

    # fish = {
    #   enable = false;
    #   package = pkgs.fish;
    #   # Set the init shell options from the one in dotfiles
    #   interactiveShellInit = ''
    #     source ~/dotfiles/fish/config.fish
    #   '';
    #   functions = {
    #     _tide_item_mise_java = {
    #       body = ''
    #         if path is $_tide_parent_dirs/.mise.local.toml
    #           set -l v (mise current java)
    #             _tide_print_item   mise_java          "$tide_java_icon $v"
    #         end
    #             '';
    #     };
    #     _tide_item_aws_vault = {
    #       body = ''
    #         if test -n "$AWS_VAULT"
    #             _tide_print_item  aws_vault           "$tide_aws_icon $AWS_VAULT $AWS_REGION"
    #         end
    #             '';
    #     };
    #   };
    #   plugins = [
    #     {
    #       name = "tide";
    #       src = pkgs.fishPlugins.tide.src;
    #     }
    #     {
    #       name = "grc";
    #       src = pkgs.fishPlugins.grc.src;
    #     }
    #     {
    #       name = "bass";
    #       src = pkgs.fishPlugins.bass.src;
    #     }
    #     {
    #       name = "bd";
    #       src = pkgs.fishPlugins.fish-bd.src;
    #     }
    #     {
    #       name = "fzf-fish";
    #       src = pkgs.fishPlugins.fzf-fish.src;
    #     }
    #     {
    #       name = "git";
    #       src = pkgs.fishPlugins.plugin-git.src;
    #     }
    #     {
    #       name = "dracula";
    #       src = pkgs.fetchFromGitHub {
    #         owner = "dracula";
    #         repo = "fish";
    #         rev = "269cd7d76d5104fdc2721db7b8848f6224bdf554";
    #         sha256 = "Hyq4EfSmWmxwCYhp3O8agr7VWFAflcUe8BUKh50fNfY=";
    #       };
    #     }
    #   ];
    #
    # };
  };
}
