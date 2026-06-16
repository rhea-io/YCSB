{
  description = "YCSB Redis client with Rhea evalsync integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/1c8ba8d3f7634acac4a2094eef7c32ad9106532c";
    flake-utils.url = "github:numtide/flake-utils";
    evalsync = {
      url = "github:rhea-io/evalsync";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, evalsync }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ycsbVersion = "0.18.0-SNAPSHOT";

        ycsbSrc = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let
              rel = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
            in
            pkgs.lib.cleanSourceFilter path type
            && !(pkgs.lib.hasInfix "/target/" rel || pkgs.lib.hasSuffix "/target" rel);
        };

        workloadreal = ''
          recordcount=1000
          operationcount=10000000
          hdrhistogram.percentiles=50,75,90,95,99,99.9,99.99

          workload=site.ycsb.workloads.CoreWorkload
          readallfields=true

          fieldcount=1000
          fieldlength=10000

          readproportion=1
          updateproportion=0
          scanproportion=0
          insertproportion=0

          requestdistribution=uniform
        '';

        workloadreal2 = ''
          recordcount=100000
          operationcount=10000000
          hdrhistogram.percentiles=50,75,90,95,99,99.9,99.99

          workload=site.ycsb.workloads.CoreWorkload
          readallfields=false

          fieldcount=1000000
          fieldlength=1000000

          readproportion=1
          updateproportion=0
          scanproportion=0
          insertproportion=0

          requestdistribution=uniform
        '';

        evalsyncJava = evalsync.packages.${system}.java;
        runtimePath = pkgs.lib.makeBinPath [ pkgs.jre ];
        workloadrealFile = pkgs.writeText "workloadreal" workloadreal;
        workloadreal2File = pkgs.writeText "workloadreal2" workloadreal2;

        makeYcsb =
          { local_dev ? false
          }:
          pkgs.maven.buildMavenPackage {
            pname = "ycsb-redis";
            version = ycsbVersion;

            src = ycsbSrc;
            mvnHash = "sha256-FR9xOgC/Mwm39dOWwUjeFmOUlryxN1rpsWcfY52T43A=";
            mvnParameters = "-pl site.ycsb:redis-binding -am";
            doCheck = false;

            nativeBuildInputs = [
              pkgs.makeWrapper
              pkgs.python3
            ];

            mvnFetchExtraArgs.preBuild = ''
              mkdir -p "$out/.m2/io/rhea/evalsync-java/0.1.0"
              cp ${evalsyncJava}/share/maven-repository/io/rhea/evalsync-java/0.1.0/evalsync-java-0.1.0.pom \
                "$out/.m2/io/rhea/evalsync-java/0.1.0/"
              cp ${evalsyncJava}/share/maven-repository/io/rhea/evalsync-java/0.1.0/evalsync-java-0.1.0.jar \
                "$out/.m2/io/rhea/evalsync-java/0.1.0/"
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin $out/share/ycsb
              tar -xzf redis/target/ycsb-redis-binding-${ycsbVersion}.tar.gz
              cp -r ycsb-redis-binding-${ycsbVersion}/. $out/share/ycsb/
              cp ${workloadrealFile} $out/share/ycsb/workloads/workloadreal
              cp ${workloadreal2File} $out/share/ycsb/workloads/workloadreal2

              patchShebangs $out/share/ycsb/bin
              makeWrapper $out/share/ycsb/bin/ycsb $out/bin/ycsb --prefix PATH : ${runtimePath}

              runHook postInstall
            '' + pkgs.lib.optionalString local_dev ''
              mkdir -p $out/share/ycsb/build
              cp -r core/target redis/target $out/share/ycsb/build/
            '';

            meta = with pkgs.lib; {
              description = "YCSB Redis client with Rhea evalsync support";
              homepage = "https://github.com/rhea-io/YCSB";
              license = licenses.asl20;
              platforms = platforms.linux;
              mainProgram = "ycsb";
            };
          };

        ycsbRedis = makeYcsb { };
      in
      {
        packages = {
          default = ycsbRedis;
          redis = ycsbRedis;
          ycsb = ycsbRedis;
        };

        apps.default = {
          type = "app";
          program = "${ycsbRedis}/bin/ycsb";
        };

        legacyPackages.benchmarks.ycsb = {
          default = ycsbRedis;
          make = makeYcsb;
        };

        lib = {
          make = makeYcsb;
          inherit makeYcsb;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.jdk17
            pkgs.maven
            pkgs.nixpkgs-fmt
          ];
        };
      }
    );
}
