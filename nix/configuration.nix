{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix # generated at runtime by nixos-infect
    ./nvim_config.nix
    ./nvim.nix
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.git = {
    enable = true;
  };

  environment.systemPackages = [
   pkgs.devenv
   pkgs.vim
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "fuzzer";
  networking.domain = "";
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKordTXNkJUVLxfpynBvuGxt9cgCD8I/3oZ+6o1WkYL6'' ];
  system.stateVersion = "23.11";
}
