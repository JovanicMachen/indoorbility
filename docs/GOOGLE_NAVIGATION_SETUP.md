# Google navigation preparation

The iOS project includes Google's Navigation SDK 11.1.1 and the matching Maps
SDK 11.1.1. The Maps version is pinned because a newer transitive version
requires a higher minimum deployment target than the Navigation package declares.
Apple MapKit is the default outdoor routing provider, even when a local
`GoogleNavigationAPIKey` is configured. If Apple cannot load a route, the user can
explicitly choose **Try Google directions**. Google guidance displays Google route
content on a Google map and preserves the saved indoor destination. Without that
key, the app uses MapKit only. The Google journey requires
physical validation before it is relied on for navigation.

If Google rejects a route or fails to provide a route or initial guidance within
the respective 12-second deadlines, the app switches that journey to Apple
walking directions. Apple route requests still need network access. This does
not turn Apple's offline maps into an offline routing API for Indoorbility.

Before activation, use an existing Google Cloud project with billing and the
Navigation SDK for iOS and Maps SDK for iOS enabled. Create a separate API key
restricted to the `com.indoorbility.app` iOS bundle identifier and those SDKs.
Keep that key out of Git and do not reuse the server or OpenAI credentials.
An iOS SDK key is included in the app binary and is not a secret; restrictions
and quota limits reduce, but do not eliminate, misuse risk.

The session requests Google's terms dialog, and the app suppresses directional
guidance when GPS or navigation updates are stale or inaccurate. Validate the
SDK's key restrictions, routing, terms, attribution, guidance and indoor handoff
with real credentials and a measured physical walk before relying on the route.

See Google's [setup guide](https://developers.google.com/maps/documentation/navigation/ios-sdk/setup-overview)
and [custom guidance guide](https://developers.google.com/maps/documentation/navigation/ios-sdk/create-customized-guidance).
