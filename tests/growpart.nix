{
  pkgs,
  modules,
  ...
}:
pkgs.testers.runNixOSTest {
  name = "growpart";

  nodes = {
    machine =
      { pkgs, ... }:
      {
        imports = modules;

        # Attach a 512MB empty virtual disk for testing growpart
        virtualisation.emptyDiskImages = [ 512 ];

        # Create a small 50MB GPT partition on the empty disk before growpart runs
        systemd.services.prepare-disk = {
          description = "Prepare virtual disk for growpart test";
          wantedBy = [ "local-fs.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.parted
            pkgs.util-linux
          ];
          script = ''
            # Create GPT label
            parted -s /dev/vdb mklabel gpt
            # Create a small 50MB partition
            parted -s /dev/vdb mkpart primary ext4 1MiB 50MiB
            # Wait for partition node creation
            udevadm settle
          '';
        };

        services.francynox.growpart.vdb = {
          device = "/dev/vdb";
          partition = 1;
          after = [ "prepare-disk.service" ];
        };
      };
  };

  testScript = ''
    # Wait for the partition to successfully grow past 450MB (initial size was 50MB)
    min_grown_size = 450 * 1024 * 1024
    machine.wait_until_succeeds(f"test $(blockdev --getsize64 /dev/vdb1) -gt {min_grown_size}")

    # Read and log the final partition block size of /dev/vdb1 for validation
    part_size = int(machine.succeed("blockdev --getsize64 /dev/vdb1").strip())
    machine.log(f"Partition /dev/vdb1 successfully grown to: {part_size} bytes")
  '';
}
