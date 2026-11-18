{
  pkgs,
  extraPkgs ? [],
  ...
}:
let
  # Ladybird uses the header-only math functions of LLVM libc and expects their
  # headers at llvm-libc/{hdr,include,shared,src/...}, the way its vcpkg port
  # installs them (Meta/CMake/vcpkg/overlay-ports/llvm-libc). The libc packages
  # of nixpkgs only ship the public headers and static libraries, so the
  # headers are taken from the llvm-project sources at the commit of the port.
  llvm-libc-headers = let
    rev = "e54169423e7ee5d8b41c2f1b6f7a59000c901ee0";
    src = pkgs.fetchFromGitHub {
      owner = "llvm";
      repo = "llvm-project";
      inherit rev;
      sparseCheckout = [ "libc" ];
      hash = "sha256-rYvY2rTNwA3Ovy3y/hI3nTp9v8kJbhxB2gseLcZ5vWA=";
    };
  in pkgs.runCommand "llvm-libc-headers-${builtins.substring 0 12 rev}" {} ''
    cd ${src}/libc
    for directory in hdr include shared src/__support src/string/memory_utils; do
      find "$directory" -name '*.h' -exec install -Dm644 {} "$out/include/llvm-libc/{}" \;
    done
  '';

  # Ladybird bundles FFmpeg with a few patches of its own, which its sources
  # rely on (e.g. AV_HWACCEL_FLAG_LADYBIRD_CLEAR_UNUSED_REF_FRAME_MVS). Apply
  # them to the FFmpeg of nixpkgs (the same version as Ladybird's vcpkg port,
  # Meta/CMake/vcpkg/overlay-ports/ffmpeg).
  ffmpeg-ladybird = let
    rev = "73162c4dd3c60a0f4017bfb4a873ba67928014d8";
    patch = name: hash: pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/LadybirdBrowser/ladybird/${rev}/Meta/CMake/vcpkg/overlay-ports/ffmpeg/${name}.patch";
      inherit hash;
    };
  in pkgs.ffmpeg-headless.overrideAttrs (previous: {
    patches = (previous.patches or []) ++ [
      (patch "0101-vulkan-decode-dpb-distinct-no-drm-modifiers" "sha256-TR62EewSOGnxCWbse+0KNqVLrRgVB7TOGLxwt+7R/Rc=")
      (patch "0102-vulkan-av1-clear-unused-ref-frame-mvs" "sha256-Hj1bTNJpqzWiyoR+ujnY6vd/LK1A9w1mY2GN1RwD9bY=")
    ];
    # Building and running FATE for every change of the patches isn't needed here.
    doCheck = false;
  });

  # Ladybird looks up its bundled FFmpeg as libavcodec-ladybird etc. (built
  # with --build-suffix=-ladybird). Alias those pkg-config modules to the
  # patched FFmpeg above.
  ffmpeg-ladybird-pkgconfig = pkgs.runCommand "ffmpeg-ladybird-pkgconfig" {} ''
    mkdir -p $out/lib/pkgconfig
    for library in libavcodec libavformat libavutil libswresample; do
      cp ${ffmpeg-ladybird.dev}/lib/pkgconfig/$library.pc $out/lib/pkgconfig/$library-ladybird.pc
    done
  '';
in
pkgs.mkShell {
  name = "ladybird-env";

  inputsFrom = [
    pkgs.ladybird
  ];

  packages = with pkgs; [
    ccache
    clang-tools
    prettier
    icu78.dev
    dejavu_fonts
    liberation_ttf
    llvm-libc-headers
    ffmpeg-ladybird-pkgconfig
    # Ladybird pins its Rust toolchain in rust-toolchain.toml and builds with
    # -Dwarnings, so a newer rustc from nixpkgs can fail on new lints and
    # deprecations. rustup installs the pinned toolchain.
    rustup
  ] ++ extraPkgs;

  ICU_ROOT = "${pkgs.icu78.dev}";

  FONTCONFIG_FILE = pkgs.makeFontsConf {
    fontDirectories = [ pkgs.dejavu_fonts pkgs.liberation_ttf ];
  };

  # https://github.com/NixOS/nixpkgs/blob/79a8a723b9/pkgs/by-name/la/ladybird/package.nix#L144-L147
  NIX_LDFLAGS = "-lGL -lfontconfig";
}
