{
  description = "NixOS config for the 3D printer farm (OctoPrint x8 + OctoFarm)";

  inputs = {
    # Matches system.stateVersion = "26.05". Exact revision is pinned in flake.lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Source tree only (not a flake input we evaluate as a package set): the
    # last nixpkgs release that still has the Python 3.10 interpreter recipe.
    nixpkgs-py310 = {
      url = "github:NixOS/nixpkgs/nixos-25.11";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nixpkgs-py310, ... }:
    let
      system = "x86_64-linux";
    in
    {
      overlays.python310 = import ./overlays/python310.nix { inherit nixpkgs-py310; };

      # hostname is "nixos", so `nixos-rebuild switch --flake .` picks this up.
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.overlays = [ self.overlays.python310 ]; }
          ./configuration.nix
        ];
      };
    };
}
