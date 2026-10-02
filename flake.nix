{
  description = "NixOS config for the 3D printer machine";

  inputs = {
    # Matches system.stateVersion = "26.05". Exact revision is pinned in flake.lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosModules.octoprint-multi = ./nixosModules/octoprint-multi.nix;
    nixosModules.fdm-monster = ./nixosModules/fdm-monster.nix;

    overlays.default = final: prev: {
      fdm-monster = final.callPackage ./pkgs/fdm-monster { };
    };

    packages.x86_64-linux.fdm-monster =
      nixpkgs.legacyPackages.x86_64-linux.callPackage ./pkgs/fdm-monster { };

    # hostname is "nixos", so `nixos-rebuild switch --flake .` picks this up.
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.default ]; }
        self.nixosModules.octoprint-multi
        self.nixosModules.fdm-monster
        ./configuration.nix
      ];
    };
  };
}
