{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix # generated at runtime by nixos-infect
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.git = {
    enable = true;
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
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
  users.users.root.openssh.authorizedKeys.keys = [''ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJIbVTc9cPV9cEJ+uwe0T92NDb74WebWdc1cIprJrKd terraform-fuzzer'' ];
  system.stateVersion = "23.11";
}
