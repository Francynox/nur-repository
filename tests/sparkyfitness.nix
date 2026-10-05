{
  pkgs,
  modules,
  ...
}:
let
  sparkyfitnessEnv = pkgs.writeText "sparkyfitness.env" ''
    SPARKY_FITNESS_DB_PASSWORD=test-owner-password-9f2c4a7e5b1d
    SPARKY_FITNESS_APP_DB_PASSWORD=test-app-password-3d8b1f6a2c4e
    SPARKY_FITNESS_API_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    BETTER_AUTH_SECRET=dGVzdHNlY3JldHRlc3RzZWNyZXR0ZXN0c2VjcmV0dGVzdHNlY3JldDEyMw==
  '';
in
pkgs.testers.runNixOSTest {
  name = "sparkyfitness";

  nodes.sparkyfitness =
    { ... }:
    {
      imports = modules;

      services.francynox.sparkyfitness = {
        enable = true;
        frontendUrl = "http://localhost";
        environmentFile = "${sparkyfitnessEnv}";
      };
    };

  testScript = ''
    import re

    def run_checks():
      sparkyfitness.wait_for_unit("sparkyfitness-db-init.service")
      sparkyfitness.wait_for_unit("sparkyfitness.service")
      # Migrations + tsx warmup can take a few minutes on first boot.
      sparkyfitness.wait_for_open_port(3010, timeout=300)

      sparkyfitness.succeed("curl --fail -s http://127.0.0.1:3010/api/health | grep 'UP'")

      sparkyfitness.wait_for_unit("caddy.service")
      sparkyfitness.wait_for_open_port(80, timeout=30)

      sparkyfitness.succeed("curl --fail -s http://localhost/ | grep 'SparkyFitness'")

      sparkyfitness.succeed("curl --fail -s http://localhost/api/health | grep 'UP'")

    def security_score():
      out = sparkyfitness.succeed("systemd-analyze security sparkyfitness.service --no-pager")
      sparkyfitness.log(f"Security Analysis:\n{out}")

      match = re.search(r"Overall exposure level.*:\s+([0-9]+\.[0-9]+)", out)
      if not match:
        raise Exception("Failed to extract numeric security score from systemd-analyze output!")

      score = float(match.group(1))
      threshold = 2.0
      if score > threshold:
        raise Exception(f"Security regression: score {score} exceeds limit {threshold}!")

    with subtest("Run Basic Checks"):
      run_checks()

    with subtest("Verify hardening"):
      security_score()

    with subtest("Verify Service Restart"):
      sparkyfitness.succeed("systemctl restart sparkyfitness.service")
      run_checks()
  '';
}
