# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, pkgs, ... }:

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

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Dedicated printer-dashboard machine: boot straight into KDE with no
  # login prompt, then kiosk-launch the FDM Monster printer grid.
  services.displayManager.autoLogin = {
    enable = true;
    user = "linux";
  };

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

  # OctoPrint x8 (all Ender 3), one instance per printer, from pkgs.octoprint.
  # The CH340 clones share one serial number, so /dev/serial/by-id collides;
  # by-path encodes the physical USB port and stays stable as long as each
  # printer stays plugged into the same port.
  services.octoprint-multi = {
    enable = true;
    openFirewall = true;
    instances = {
      printer1 = {
        port = 5001;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:9.1:1.0-port0";
        accessControl = false;
        # Served by services.mjpg-streamer below.
        extraSettings = {
          webcam = {
            stream = "http://127.0.0.1:8080/?action=stream";
            snapshot = "http://127.0.0.1:8080/?action=snapshot";
          };
        };
      };
      printer2 = {
        port = 5002;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:9.2:1.0-port0";
        accessControl = false;
      };
      printer3 = {
        port = 5003;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:9.3:1.0-port0";
        accessControl = false;
      };
      printer4 = {
        port = 5004;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:9.4:1.0-port0";
        accessControl = false;
      };
      printer5 = {
        port = 5005;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:10.1:1.0-port0";
        accessControl = false;
      };
      printer6 = {
        port = 5006;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:10.2:1.0-port0";
        accessControl = false;
      };
      printer7 = {
        port = 5007;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:10.3:1.0-port0";
        accessControl = false;
      };
      printer8 = {
        port = 5008;
        serialPort = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:10.4.3:1.0-port0";
        accessControl = false;
      };
    };
  };

  # MJPEG webcam stream for printer1's Logitech C920 (stable by-id path so it
  # survives being replugged into a different USB port). Consumed locally by
  # OctoPrint's embedded webcam view and the FDM Monster printer grid, both of
  # which run on this same machine, hence the 127.0.0.1 URLs above.
  services.mjpg-streamer = {
    enable = true;
    inputPlugin = "input_uvc.so -d /dev/v4l/by-id/usb-046d_HD_Pro_Webcam_C920_85CC92EF-video-index0 -r 1280x720 -f 15";
    outputPlugin = "output_http.so -w @www@ -p 8080";
  };
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # FDM Monster (port 4000) with all eight OctoPrint instances pre-registered.
  services.fdm-monster = {
    enable = true;
    openFirewall = true;
    registerOctoprintMulti = true;
  };

  # Install firefox.
  programs.firefox.enable = true;

  # Kiosk-launch the FDM Monster printer grid once the KDE session (and the
  # fdm-monster service) is up.
  systemd.user.services.printer-grid-kiosk = {
    description = "Open FDM Monster printer grid in kiosk mode";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "printer-grid-kiosk" ''
        set -eu
        for _ in $(seq 1 60); do
          ${pkgs.curl}/bin/curl -fs http://localhost:4000/ >/dev/null 2>&1 && break
          sleep 2
        done
        exec ${pkgs.firefox}/bin/firefox --kiosk http://localhost:4000/printer-grid
      '';
      Restart = "no";
    };
  };

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
      orca-slicer
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
  services.openssh.enable = true;

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
