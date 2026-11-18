// The `metalui` release version (ruling SC-J).

/// The version of this `metalui` and of the MetalUI release it scaffolds
/// against: the single source of truth. A release version is `MAJOR.MINOR.PATCH`;
/// anything else (`0.2.0-dev`) marks a development tree, which never writes a
/// version requirement into a generated manifest. The release workflow
/// (`.github/workflows/release.yml`) fails unless the pushed tag is `v` plus
/// this constant.
package let metaluiVersion = "0.1.0"
