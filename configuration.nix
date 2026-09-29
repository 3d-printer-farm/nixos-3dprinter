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

  # OctoPrint x8, one Docker container per printer.
  # Printer serial devices aren't known yet - once a printer is plugged in,
  # add e.g. `extraOptions = [ "--device=/dev/ttyUSB0" ];` to its container.
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers = lib.listToAttrs (map
    (n: {
      name = "octoprint-${toString n}";
      value = {
        image = "octoprint/octoprint:latest";
        autoStart = true;
        ports = [ "${toString (5000 + n)}:80" ];
        volumes = [ "/var/lib/octoprint/octoprint-${toString n}:/octoprint" ];
      };
    })
    (lib.range 1 8));

  # MongoDB for OctoFarm.
  services.mongodb.enable = true;

  # OctoFarm, run natively (no Docker) as a systemd service.
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
        git clone https://github.com/kimseungsu-zzz/OctoFarm.git /var/lib/octofarm/app
      else
        git -C /var/lib/octofarm/app pull
      fi
      cd /var/lib/octofarm/app
      npm run install-server
      npm run install-client
      npm run build-client
      printf 'NODE_ENV=production\nMONGO=mongodb://127.0.0.1:27017/octofarm\nOCTOFARM_PORT=4000\n' > .env
    '';
  };

  systemd.services.octofarm = {
    description = "OctoFarm server";
    after = [ "octofarm-setup.service" "mongodb.service" "network-online.target" ];
    requires = [ "octofarm-setup.service" "mongodb.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.nodejs ];
    environment = {
      HOME = "/var/lib/octofarm";
      NODE_ENV = "production";
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
