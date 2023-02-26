#tryinclude "manual_version.sp"
#if !defined PLUGIN_VERSION
#define PLUGIN_VERSION "0.13.0"
#endif

// This MUST be the latest version in x.y.z semver format followed by -dev.
// If this is not consistently applied, the update-checker might malfunction.
// In official releases, the CI flow will remove the -dev suffix when compiling the plugin.
// In development pre-releases, dev is replaced with the first 6 characters of the commit hash.
