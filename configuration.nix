# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, pkgs, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Seoul";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ko_KR.UTF-8";
    LC_IDENTIFICATION = "ko_KR.UTF-8";
    LC_MEASUREMENT = "ko_KR.UTF-8";
    LC_MONETARY = "ko_KR.UTF-8";
    LC_NAME = "ko_KR.UTF-8";
    LC_NUMERIC = "ko_KR.UTF-8";
    LC_PAPER = "ko_KR.UTF-8";
    LC_TELEPHONE = "ko_KR.UTF-8";
    LC_TIME = "ko_KR.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the XFCE Desktop Environment.
  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.desktopManager.xfce.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    # jack.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."linux" = {
    isNormalUser = true;
    description = "3d_printer";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [
    #  thunderbird
    ];
  };

  # Enable Docker.
  virtualisation.docker.enable = true;

  # OctoPrint x8, run natively from the 3d-printer-farm fork (source only, no
  # Docker image). The fork is OctoPrint 1.7.3, whose dependency pins
  # (Flask<2, tornado<7, PyYAML<6, wrapt<1.13, ...) only build on an older
  # Python: nixos-26.05 no longer ships python310, so pkgs.python310 comes from
  # the custom overlay in overlays/python310.nix (wired up in flake.nix).
  # Each instance has its own basedir (/var/lib/octoprint/N) and port (500N).
  # Printer serial devices aren't known yet - once a printer is plugged in,
  # point the instance at it in OctoPrint's serial settings (the user is in
  # the dialout group). Prefer /dev/serial/by-id/* over /dev/ttyUSBn.
  users.groups.octoprint = { };
  users.users.octoprint = {
    isSystemUser = true;
    group = "octoprint";
    extraGroups = [ "dialout" ];
    home = "/var/lib/octoprint";
    createHome = true;
  };

  systemd.services.octoprint-setup = {
    description = "Clone and install OctoPrint";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.git pkgs.python310 pkgs.gcc pkgs.gnumake ];
    environment.HOME = "/var/lib/octoprint";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "octoprint";
      Group = "octoprint";
      WorkingDirectory = "/var/lib/octoprint";
    };
    script = ''
      set -e
      if [ ! -d src/.git ]; then
        git clone --branch main https://github.com/3d-printer-farm/OctoPrint.git src
      else
        git -C src pull
      fi
      [ -d venv ] || python -m venv venv
      venv/bin/pip install --upgrade pip setuptools wheel
      venv/bin/pip install -e src
    '';
  };

  # Template unit: octoprint@N serves instance N on port 500N.
  systemd.services."octoprint@" = {
    description = "OctoPrint instance %i";
    after = [ "octoprint-setup.service" ];
    requires = [ "octoprint-setup.service" ];
    environment.HOME = "/var/lib/octoprint";
    serviceConfig = {
      User = "octoprint";
      Group = "octoprint";
      ExecStart = "/var/lib/octoprint/venv/bin/octoprint serve --host 0.0.0.0 --port 500%i --basedir /var/lib/octoprint/%i";
      Restart = "on-failure";
    };
  };
  systemd.targets.multi-user.wants =
    map (n: "octoprint@${toString n}.service") (lib.range 1 8);

  # OctoFarm, run natively (no Docker) as a systemd service.
  # The 3d-printer-farm fork replaced MongoDB with node:sqlite, so no database
  # server is needed; it only requires Node >= 22.5.
  users.groups.octofarm = { };
  users.users.octofarm = {
    isSystemUser = true;
    group = "octofarm";
    home = "/var/lib/octofarm";
    createHome = true;
  };

  systemd.services.octofarm-setup = {
    description = "Clone and build OctoFarm";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.git pkgs.nodejs ];
    environment = {
      HOME = "/var/lib/octofarm";
      NPM_CONFIG_CACHE = "/var/lib/octofarm/.npm";
      # sharp's prebuilt libvips needs libstdc++ on NixOS.
      LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = "octofarm";
      Group = "octofarm";
      WorkingDirectory = "/var/lib/octofarm";
    };
    script = ''
      set -e
      if [ ! -d /var/lib/octofarm/app/.git ]; then
        git clone https://github.com/3d-printer-farm/OctoFarm.git /var/lib/octofarm/app
      else
        git -C /var/lib/octofarm/app pull
      fi
      cd /var/lib/octofarm/app
      npm run install-server
      npm run install-client
      npm run build-client
      printf 'NODE_ENV=production\nOCTOFARM_PORT=4000\nOCTOFARM_SQLITE_PATH=/var/lib/octofarm/octofarm.db\n' > .env
    '';
  };

  systemd.services.octofarm = {
    description = "OctoFarm server";
    after = [ "octofarm-setup.service" "network-online.target" ];
    requires = [ "octofarm-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.nodejs pkgs.git ];
    environment = {
      HOME = "/var/lib/octofarm";
      NODE_ENV = "production";
      OCTOFARM_PORT = "4000";
      OCTOFARM_SQLITE_PATH = "/var/lib/octofarm/octofarm.db";
      # sharp's prebuilt libvips needs libstdc++ on NixOS.
      LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
    };
    serviceConfig = {
      Type = "simple";
      User = "octofarm";
      Group = "octofarm";
      WorkingDirectory = "/var/lib/octofarm/app/server";
      ExecStart = "${pkgs.nodejs}/bin/node app.js";
      Restart = "on-failure";
    };
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable flakes and the new nix command.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
      git
      gh
      claude-code
      nodejs
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # OctoFarm (4000) and the 8 OctoPrint instances (5001-5008).
  networking.firewall.allowedTCPPorts = [ 4000 ] ++ (lib.range 5001 5008);
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}
