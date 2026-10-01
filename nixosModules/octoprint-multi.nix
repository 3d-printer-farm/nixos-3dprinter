# Runs several independent OctoPrint instances (one per printer) from the
# nixpkgs `octoprint` package. nixpkgs' own services.octoprint only supports a
# single instance, so this module defines one systemd service per instance,
# each with its own basedir, port and serial device.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.octoprint-multi;
  yaml = pkgs.formats.yaml { };

  instanceOpts = { name, ... }: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = "HTTP port of this instance.";
      };

      serialPort = lib.mkOption {
        type = lib.types.str;
        example = "/dev/serial/by-path/pci-0000:00:14.0-usb-0:9.1:1.0-port0";
        description = ''
          Serial device of the printer. Prefer a stable /dev/serial/by-id or
          /dev/serial/by-path symlink.
        '';
      };

      baudrate = lib.mkOption {
        type = lib.types.int;
        default = 115200;
      };

      autoconnect = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      accessControl = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether OctoPrint requires a login. When false, anyone who can reach
          the port has full control of the printer, so only do this on a
          trusted network. Applied on every start, including to existing
          config.yaml files.
        '';
      };

      profile = {
        name = lib.mkOption { type = lib.types.str; default = "Ender 3"; };
        model = lib.mkOption { type = lib.types.str; default = "Creality Ender 3"; };
        width = lib.mkOption { type = lib.types.int; default = 220; };
        depth = lib.mkOption { type = lib.types.int; default = 220; };
        height = lib.mkOption { type = lib.types.int; default = 250; };
        heatedBed = lib.mkOption { type = lib.types.bool; default = true; };
        nozzleDiameter = lib.mkOption { type = lib.types.float; default = 0.4; };
      };

      extraSettings = lib.mkOption {
        type = yaml.type;
        default = { };
        description = "Extra config.yaml settings, merged into the seeded file.";
      };
    };
  };

  stateDir = name: "octoprint/${name}";

  configFile = name: i: yaml.generate "octoprint-${name}-config.yaml" (lib.recursiveUpdate {
    serial = {
      port = i.serialPort;
      baudrate = i.baudrate;
      autoconnect = i.autoconnect;
    };
    printerProfiles.default = "_default";
  } i.extraSettings);

  profileFile = name: i: yaml.generate "octoprint-${name}-profile.yaml" {
    id = "_default";
    name = i.profile.name;
    model = i.profile.model;
    color = "default";
    volume = {
      width = i.profile.width;
      depth = i.profile.depth;
      height = i.profile.height;
      formFactor = "rectangular";
      origin = "lowerleft";
      custom_box = false;
    };
    heatedBed = i.profile.heatedBed;
    heatedChamber = false;
    extruder = {
      count = 1;
      offsets = [ [ 0 0 ] ];
      nozzleDiameter = i.profile.nozzleDiameter;
      sharedNozzle = false;
    };
    axes = {
      x = { speed = 6000; inverted = false; };
      y = { speed = 6000; inverted = false; };
      z = { speed = 200; inverted = false; };
      e = { speed = 300; inverted = false; };
    };
  };

  # Seeds config only when missing, so changes made in the OctoPrint UI survive
  # restarts and rebuilds. accessControl.enabled is the one setting enforced on
  # every start.
  seedScript = name: i: pkgs.writeShellScript "octoprint-${name}-seed" ''
    set -eu
    base="$STATE_DIRECTORY"
    mkdir -p "$base/printerProfiles"
    [ -e "$base/config.yaml" ] || install -m 0640 ${configFile name i} "$base/config.yaml"
    [ -e "$base/printerProfiles/_default.profile" ] || \
      install -m 0640 ${profileFile name i} "$base/printerProfiles/_default.profile"
    ${cfg.package}/bin/octoprint --basedir "$base" config set --bool \
      accessControl.enabled ${lib.boolToString i.accessControl}
  '';
in
{
  options.services.octoprint-multi = {
    enable = lib.mkEnableOption "multiple OctoPrint instances";

    package = lib.mkPackageOption pkgs "octoprint" { };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address the instances listen on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the TCP port of every instance.";
    };

    user = lib.mkOption { type = lib.types.str; default = "octoprint"; };
    group = lib.mkOption { type = lib.types.str; default = "octoprint"; };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceOpts);
      default = { };
      description = "OctoPrint instances, keyed by name. State lives in /var/lib/octoprint/<name>.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = let ports = lib.mapAttrsToList (_: i: i.port) cfg.instances;
                    in lib.length ports == lib.length (lib.unique ports);
        message = "services.octoprint-multi: instance ports must be unique.";
      }
    ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      extraGroups = [ "dialout" ];
    };

    systemd.services = lib.mapAttrs' (name: i:
      lib.nameValuePair "octoprint-${name}" {
        description = "OctoPrint instance ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment.HOME = "/var/lib/${stateDir name}";
        serviceConfig = {
          User = cfg.user;
          Group = cfg.group;
          StateDirectory = stateDir name;
          StateDirectoryMode = "0750";
          ExecStartPre = seedScript name i;
          ExecStart = lib.escapeShellArgs [
            "${cfg.package}/bin/octoprint" "serve"
            "--host" cfg.host
            "--port" (toString i.port)
            "--basedir" "/var/lib/${stateDir name}"
          ];
          Restart = "on-failure";
        };
      }) cfg.instances;

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall (lib.mapAttrsToList (_: i: i.port) cfg.instances);
  };
}
