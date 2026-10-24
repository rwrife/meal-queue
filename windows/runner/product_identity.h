// Product identity for Meal Queue.
//
// The portable (zip) build carries no MSIX package identity. The values below
// are the single source of truth for the identity used when packaging an MSIX
// (issue #8 release pipeline) so it can never drift from the Android
// applicationId / iOS bundle id `com.infinityball.mealqueue`.
//
// MSIX identity name must be all-lowercase alphanumeric + dots, hence
// `cominfinityball.mealqueue` (matches toolchain.json windows_identity_name).
#define MQ_PACKAGE_IDENTITY_NAME    "cominfinityball.mealqueue"
#define MQ_PACKAGE_DISPLAY_NAME     "Meal Queue"
#define MQ_PACKAGE_PUBLISHER        "CN=InfinityBall"
