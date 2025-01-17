{ lib, stdenv, llvm_meta, fetch, fetchpatch, substituteAll, cmake, libxml2, libllvm, version, clang-tools-extra_src, python3
, buildLlvmTools
, fixDarwinDylibNames
, enableManpages ? false
, enablePolly ? false
}:

let
  self = stdenv.mkDerivation ({
    pname = "clang";
    inherit version;

    src = fetch "clang" "02ajkij85966vd150iy246mv16dsaph1kfi0y8wnncp8w6nar5hg";
    inherit clang-tools-extra_src;

    unpackPhase = ''
      unpackFile $src
      mv clang-* clang
      sourceRoot=$PWD/clang
      unpackFile ${clang-tools-extra_src}
      mv clang-tools-extra-* $sourceRoot/tools/extra
    '';

    nativeBuildInputs = [ cmake python3 ]
      ++ lib.optional enableManpages python3.pkgs.sphinx
      ++ lib.optional stdenv.hostPlatform.isDarwin fixDarwinDylibNames;

    buildInputs = [ libxml2 libllvm ];

    cmakeFlags = [
      "-DCMAKE_CXX_FLAGS=-std=c++14"
      "-DCLANGD_BUILD_XPC=OFF"
      "-DLLVM_CONFIG_PATH=${libllvm.dev}/bin/llvm-config${lib.optionalString (stdenv.hostPlatform != stdenv.buildPlatform) "-native"}"
    ] ++ lib.optionals enableManpages [
      "-DCLANG_INCLUDE_DOCS=ON"
      "-DLLVM_ENABLE_SPHINX=ON"
      "-DSPHINX_OUTPUT_MAN=ON"
      "-DSPHINX_OUTPUT_HTML=OFF"
      "-DSPHINX_WARNINGS_AS_ERRORS=OFF"
    ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "-DLLVM_TABLEGEN_EXE=${buildLlvmTools.llvm}/bin/llvm-tblgen"
      "-DCLANG_TABLEGEN=${buildLlvmTools.libclang.dev}/bin/clang-tblgen"
    ] ++ lib.optionals enablePolly [
      "-DWITH_POLLY=ON"
      "-DLINK_POLLY_INTO_TOOLS=ON"
    ];


    patches = [
      ./purity.patch
      # https://reviews.llvm.org/D51899
      ./gnu-install-dirs.patch
      # Revert: [Driver] Default to -fno-common for all targets
      # https://reviews.llvm.org/D75056
      #
      # Maintains compatibility with packages that haven't been fixed yet, and
      # matches gcc10's configuration in nixpkgs.
      (fetchpatch {
        revert = true;
        url = "https://github.com/llvm/llvm-project/commit/0a9fc9233e172601e26381810d093e02ef410f65.diff";
        stripLen = 1;
        excludes = [ "docs/*" "test/*" ];
        sha256 = "0gxgmi0qbm89mq911dahallhi8m6wa9vpklklqmxafx4rplrr8ph";
      })
      (substituteAll {
        src = ../../clang-11-12-LLVMgold-path.patch;
        libllvmLibdir = "${libllvm.lib}/lib";
      })
    ];

    postPatch = ''
      sed -i -e 's/DriverArgs.hasArg(options::OPT_nostdlibinc)/true/' \
             -e 's/Args.hasArg(options::OPT_nostdlibinc)/true/' \
             lib/Driver/ToolChains/*.cpp

      # Patch for standalone doc building
      sed -i '1s,^,find_package(Sphinx REQUIRED)\n,' docs/CMakeLists.txt
    '' + lib.optionalString stdenv.hostPlatform.isMusl ''
      sed -i -e 's/lgcc_s/lgcc_eh/' lib/Driver/ToolChains/*.cpp
    '' + lib.optionalString stdenv.hostPlatform.isDarwin ''
      substituteInPlace tools/extra/clangd/CMakeLists.txt \
        --replace "NOT HAVE_CXX_ATOMICS64_WITHOUT_LIB" FALSE
    '';

    outputs = [ "out" "lib" "dev" "python" ];

    postInstall = ''
      ln -sv $out/bin/clang $out/bin/cpp

      # Move libclang to 'lib' output
      moveToOutput "lib/libclang.*" "$lib"
      moveToOutput "lib/libclang-cpp.*" "$lib"
      substituteInPlace $out/lib/cmake/clang/ClangTargets-release.cmake \
          --replace "\''${_IMPORT_PREFIX}/lib/libclang." "$lib/lib/libclang." \
          --replace "\''${_IMPORT_PREFIX}/lib/libclang-cpp." "$lib/lib/libclang-cpp."

      mkdir -p $python/bin $python/share/clang/
      mv $out/bin/{git-clang-format,scan-view} $python/bin
      if [ -e $out/bin/set-xcode-analyzer ]; then
        mv $out/bin/set-xcode-analyzer $python/bin
      fi
      mv $out/share/clang/*.py $python/share/clang
      rm $out/bin/c-index-test

      mkdir -p $dev/bin
      cp bin/clang-tblgen $dev/bin
    '';

    passthru = {
      isClang = true;
      inherit libllvm;
    };

    meta = llvm_meta // {
      homepage = "https://clang.llvm.org/";
      description = "A C language family frontend for LLVM";
      longDescription = ''
        The Clang project provides a language front-end and tooling
        infrastructure for languages in the C language family (C, C++, Objective
        C/C++, OpenCL, CUDA, and RenderScript) for the LLVM project.
        It aims to deliver amazingly fast compiles, extremely useful error and
        warning messages and to provide a platform for building great source
        level tools. The Clang Static Analyzer and clang-tidy are tools that
        automatically find bugs in your code, and are great examples of the sort
        of tools that can be built using the Clang frontend as a library to
        parse C/C++ code.
      '';
    };
  } // lib.optionalAttrs enableManpages {
    pname = "clang-manpages";

    buildPhase = ''
      make docs-clang-man
    '';

    installPhase = ''
      mkdir -p $out/share/man/man1
      # Manually install clang manpage
      cp docs/man/*.1 $out/share/man/man1/
    '';

    outputs = [ "out" ];

    doCheck = false;

    meta = llvm_meta // {
      description = "man page for Clang ${version}";
    };
  });
in self
