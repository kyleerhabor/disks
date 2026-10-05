{ fetchzip, lib, stdenvNoCC }: stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "disks";
  version = "1.0.7";
  src = fetchzip {
    url = "https://github.com/kyleerhabor/disks/releases/download/v${finalAttrs.version}/Disks.app.zip";
    hash = "sha256-kN75v5SaQ19qT/7okIQ/RI1MRFCYlgMOp6HtLJThTpI=";
    stripRoot = false;
  };
  installPhase = ''
    mkdir -p $out/Applications
    cp -R $src/Disks.app $out/Applications/
  '';
  meta.platforms = lib.platforms.darwin;
  meta.sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
})
