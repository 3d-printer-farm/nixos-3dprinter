# FDM Monster service, optionally pre-registering every instance defined by
# services.octoprint-multi as an OctoPrint printer.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.fdm-monster;
  octo = config.services.octoprint-multi;
  stateDir = "/var/lib/fdm-monster";
  url = "http://127.0.0.1:${toString cfg.port}";

  printerOpts = { name, ... }: {
    options = {
      name = lib.mkOption { type = lib.types.str; default = name; };
      url = lib.mkOption {
        type = lib.types.str;
        example = "http://127.0.0.1:5001";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.str;
        description = "File holding the OctoPrint API key. Read as root by the provisioning unit.";
      };
    };
  };

  printers = cfg.printers
    // lib.optionalAttrs cfg.registerOctoprintMulti (lib.mapAttrs
      (n: i: {
        name = n;
        url = "http://${cfg.octoprintHost}:${toString i.port}";
        apiKeyFile = "/var/lib/octoprint/${n}/api.key";
      })
      octo.instances);

  printersJson = pkgs.writeText "fdm-monster-printers.json" (builtins.toJSON
    (lib.mapAttrsToList (_: p: { inherit (p) name url apiKeyFile; }) printers));

  provisionScript = pkgs.writeShellScript "fdm-monster-provision" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.coreutils pkgs.gnugrep ]}
    base=${url}/api

    for _ in $(seq 1 60); do
      curl -fs "$base/auth/login-required" >/dev/null && break
      sleep 2
    done

    pw=$(cat /var/lib/fdm-monster-provision/root-password)

    # First-time wizard; answers 403 once it has been completed.
    jq -n --arg u ${lib.escapeShellArg cfg.rootUsername} --arg p "$pw" \
      --argjson lr ${lib.boolToString cfg.loginRequired} \
      '{loginRequired:$lr, registration:false, rootUsername:$u, rootPassword:$p}' |
      curl -s -o /dev/null -X POST -H 'Content-Type: application/json' -d @- "$base/first-time-setup/complete" || true

    token=$(jq -n --arg u ${lib.escapeShellArg cfg.rootUsername} --arg p "$pw" '{username:$u, password:$p}' |
      curl -fs -X POST -H 'Content-Type: application/json' -d @- "$base/auth/login" | jq -r '.token')
    auth="Authorization: Bearer $token"

    existing=$(curl -fs -H "$auth" "$base/printer" | jq -r '.[].printerURL')

    jq -c '.[]' ${printersJson} | while read -r p; do
      purl=$(echo "$p" | jq -r .url)
      if echo "$existing" | grep -qxF "$purl"; then continue; fi
      key=$(cat "$(echo "$p" | jq -r .apiKeyFile)")
      # forceSave: register even if the OctoPrint instance is not up yet.
      echo "$p" | jq --arg k "$key" \
        '{name, printerURL:.url, printerType:0, apiKey:$k, enabled:true}' |
        curl -fs -X POST -H "$auth" -H 'Content-Type: application/json' -d @- "$base/printer?forceSave=true" >/dev/null
      echo "registered $purl"
    done
  '';
in
{
  options.services.fdm-monster = {
    enable = lib.mkEnableOption "FDM Monster printer farm manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fdm-monster;
      defaultText = lib.literalExpression "pkgs.fdm-monster";
    };

    port = lib.mkOption { type = lib.types.port; default = 4000; };
    openFirewall = lib.mkOption { type = lib.types.bool; default = false; };

    loginRequired = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Require login to the web UI. Disabled by default to match the
        login-less OctoPrint instances; only do this on a trusted network.
      '';
    };

    rootUsername = lib.mkOption { type = lib.types.str; default = "admin"; };

    registerOctoprintMulti = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Register every services.octoprint-multi instance as a printer.";
    };

    octoprintHost = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Host used in the URLs of auto-registered OctoPrint instances.";
    };

    printers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule printerOpts);
      default = { };
      description = "Additional OctoPrint printers to register.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.fdm-monster = { };
    users.users.fdm-monster = {
      isSystemUser = true;
      group = "fdm-monster";
    };

    systemd.services.fdm-monster = {
      description = "FDM Monster";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        SERVER_PORT = toString cfg.port;
        MEDIA_PATH = "${stateDir}/media";
        DATABASE_PATH = "${stateDir}/database";
        OVERRIDE_LOGIN_REQUIRED = lib.boolToString cfg.loginRequired;
        OVERRIDE_REGISTRATION_ENABLED = "false";
        ENABLE_CLIENT_DIST_AUTO_UPDATE = "false";
      };
      serviceConfig = {
        User = "fdm-monster";
        Group = "fdm-monster";
        StateDirectory = "fdm-monster";
        WorkingDirectory = stateDir;
        # The client bundle ships with the package; seed it instead of letting
        # the server download it from GitHub.
        ExecStartPre = pkgs.writeShellScript "fdm-monster-seed" ''
          set -eu
          dst=${stateDir}/media/client-dist
          have=$(${pkgs.jq}/bin/jq -r .version "$dst/package.json" 2>/dev/null || true)
          if [ "$have" != "${cfg.package.clientVersion}" ]; then
            rm -rf "$dst"
            mkdir -p "$dst"
            cp -r --no-preserve=mode ${cfg.package}/share/fdm-monster/client-dist/. "$dst"
          fi
        '';
        ExecStart = "${cfg.package}/bin/fdm-monster";
        Restart = "on-failure";
      };
    };

    systemd.services.fdm-monster-provision = lib.mkIf (printers != { }) {
      description = "Register printers in FDM Monster";
      wantedBy = [ "multi-user.target" ];
      after = [ "fdm-monster.service" ]
        ++ lib.optionals cfg.registerOctoprintMulti
          (map (n: "octoprint-${n}.service") (lib.attrNames octo.instances));
      requires = [ "fdm-monster.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Runs as root: needs to read the octoprint-owned api.key files.
        # The generated admin password lives in a separate root-only dir.
        StateDirectory = "fdm-monster-provision";
        StateDirectoryMode = "0700";
        ExecStartPre = pkgs.writeShellScript "fdm-monster-rootpw" ''
          f=/var/lib/fdm-monster-provision/root-password
          [ -s "$f" ] || (umask 077; head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$f")
        '';
        ExecStart = provisionScript;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
