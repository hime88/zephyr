// =========================================================================
// MARK: - CSDL3_image Stub
//
// SPM requires at least one C source file per Clang target. Without one the
// target still produces a module (the module map and sdl3_image.h shim are
// enough for `import CSDL3_image`), but Swift 6.4's default build engine still
// lists `<target>.o` / `<target>.objlib` among the link inputs and fails with
//
//   error: Build input files cannot be found: '.../CSDL3_image.o'
//
// The older native engine tolerated the header-only target; this keeps both
// working. Intentionally empty — the module map and the linker settings are what
// matter, and all SDL3_image functionality comes from the SDL3_image library
// linked via Package.swift.
// =========================================================================

// One symbol, so the translation unit cannot be optimised down to nothing: the
// build system is looking for the object file itself, not for its contents.
// Never called, and `--gc-sections`-friendly.
void zephyr_spm_stub_csdl3_image(void) {}
