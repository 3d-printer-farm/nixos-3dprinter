{
  description = "NixOS config for the 3D printer machine";

  inputs = {
    # Matches system.stateVersion = "26.05". Exact revision is pinned in flake.lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }: {
    # hostname is "nixos", so `nixos-rebuild switch --flake .` picks this up.
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
