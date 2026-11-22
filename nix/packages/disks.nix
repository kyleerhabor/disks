{ fetchzip, lib, stdenvNoCC }: stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "disks";
  version = "1.0.8.1";
  src = fetchzip {
    url = "https://github.com/kyleerhabor/disks/releases/download/v${finalAttrs.version}/Disks.app.zip";
    hash = "sha256-Vhr8Y9WbgJrPYXnUeQrME6YoWSl8asYTWeoDOufoF7I=";
    stripRoot = false;
  };
  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R $src/Disks.app $out/Applications/
    runHook postInstall
  '';
  meta.platforms = lib.platforms.darwin;
  meta.sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
})
