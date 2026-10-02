# FDM Monster: bulk 3D printer farm manager (OctoPrint, Moonraker, PrusaLink, Bambu).
# https://github.com/fdm-monster/fdm-monster
#
# The server normally downloads its web client from GitHub at first start.
# That is impossible in a sandboxed build and awkward at runtime, so the client
# bundle is fetched here and exposed as `$out/share/fdm-monster/client-dist`
# (the NixOS module copies it into the media directory).
{ lib
, stdenv
, fetchurl
, nodejs_22
, yarn-berry
, node-gyp
, python3
, pkg-config
, makeWrapper
, unzip
}:

let
  nodejs = nodejs_22;
  yarn = yarn-berry.override { inherit nodejs; };

  version = "2.1.1";
  clientVersion = "2.4.2"; # must match "@fdm-monster/client-next" / defaultClientMinimum

  clientDist = fetchurl {
    url = "https://github.com/fdm-monster/fdm-monster-client-next/releases/download/${clientVersion}/dist-client-${clientVersion}.zip";
    hash = "sha256-GV45BhJL+e6T6FNLBZDWVsNSA50zoKPARD35P5q41H0=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "fdm-monster";
  inherit version;

  src = fetchurl {
    url = "https://github.com/fdm-monster/fdm-monster/archive/refs/tags/${version}.tar.gz";
    hash = "sha256-3VQE6SQCCSuU2JLWXmDHeX6sQnp3NP42bWBIPA+2wsA=";
  };

  # yarn.lock omits hashes for optional/platform-specific deps (e.g. esbuild,
  # lightningcss, oxlint native binaries); this file fills them in. Regenerate
  # with `yarn-berry-fetcher missing-hashes yarn.lock` after bumping version.
  missingHashes = ./missing-hashes.json;

  # Fill in on first build: `nix build .#fdm-monster` prints the real hash.
  offlineCache = yarn.fetchYarnBerryDeps {
    inherit (finalAttrs) src missingHashes;
    hash = "sha256-mJiwwxVbNgh0d5ORs9Obog2JUFDI77oyTQbV4FcA+/Y=";
  };

  nativeBuildInputs = [
    nodejs
    yarn
    yarn.yarnBerryConfigHook
    node-gyp
    python3
    pkg-config
    makeWrapper
    unzip
  ];

  buildPhase = ''
    runHook preBuild

    # Install scripts are disabled (.yarnrc.yml), so compile the one native
    # module (better-sqlite3) by hand against the Nix node headers.
    (cd node_modules/better-sqlite3 && node-gyp rebuild --release --nodedir=${nodejs})

    yarn build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/lib/fdm-monster
    mkdir -p $app $out/bin $out/share/fdm-monster/client-dist
    cp -r dist node_modules package.json $app/

    # Workspace symlink to a dev-only package (mock servers, diagnostics) not
    # used by the server's own build output; drop it instead of shipping
    # packages/consoles just to satisfy the link.
    rm -f $app/node_modules/@fdm-monster/consoles

    unzip -q ${clientDist} -d $out/share/fdm-monster/client-dist

    # The server resolves package.json relative to its own location and keeps
    # all state in MEDIA_PATH / DATABASE_PATH, so those are set by the module.
    makeWrapper ${nodejs}/bin/node $out/bin/fdm-monster \
      --add-flags $app/dist/index.js \
      --set NODE_ENV production \
      --set ENABLE_CLIENT_DIST_AUTO_UPDATE false

    runHook postInstall
  '';

  passthru = { inherit clientDist clientVersion; };

  meta = {
    description = "Bulk OctoPrint, Klipper, PrusaLink and Bambu Lab manager for 3D printer farms";
    homepage = "https://github.com/fdm-monster/fdm-monster";
    license = lib.licenses.agpl3Plus;
    mainProgram = "fdm-monster";
    platforms = lib.platforms.linux;
  };
})
