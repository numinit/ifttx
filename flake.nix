{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-parts.flakeModules.easyOverlay
      ];

      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        {
          system,
          pkgs,
          inputs',
          final,
          ...
        }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [
              self.overlays.default
            ];
          };

          legacyPackages = pkgs;

          overlayAttrs = {
            fldigi = pkgs.fldigi.overrideAttrs (_: {
              patches = [ ./0001-Add-FLDIGI_CREATE_CONFIG_AND_EXIT.patch ];
            });

            ifttx = pkgs.writeShellApplication {
              name = "ifttx";
              text = ''
                exec ruby ${./ifttx.rb} "$@"
              '';
              runtimeInputs = with final; [
                ruby
                fldigi
                xvfb-run
              ];
            };
          };

          devShells.default = final.mkShell {
            buildInputs = with final; [
              ruby
              fldigi
              xvfb-run
            ];
          };

          packages.default = final.ifttx;

          apps.default = {
            type = "app";
            program = "${final.ifttx}";
          };
        };
    };
}
