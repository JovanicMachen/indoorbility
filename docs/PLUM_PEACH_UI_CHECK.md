# Plum & Peach interface update

The Home screen uses a warm light background, white search/results surfaces, plum headings/actions and a peach microphone halo. Search moves upward and the title becomes smaller while editing; the microphone dock hides while the keyboard is open. Existing listening edge glow remains active and respects Reduce Motion. Home, Help and Settings remain the only tabs.

Home now searches MapKit and configured Google Places after 450 ms without typing, without waiting for an LLM. Cancellation/generation checks prevent older responses from replacing the current query. Apple results open the existing destination confirmation and in-app MapKit route. Google results are separately attributed supplementary information, not transferred to an Apple map. Existing Google discovery no longer has a destination link that launches Google Maps externally. Friend Center's information screen includes an in-app building-directions search.

One live Google Places request for Friend Center Princeton University succeeded and returned a result using existing local configuration. No credential was printed or changed. This does not validate network reliability on the physical iPhone or prove indoor positioning. Google search still requires network, billing and permitted key configuration.

Indoor room routes remain limited to reviewed geometry; source-known Friend Center rooms do not become routable from this UI change. No sensor, routing, closure or agent execution logic was replaced. Avoid-stairs preferences still prevent claiming an unverified outdoor route is step-free.

Validation: final unsigned iPhone SDK build passed. The existing accessibility preferences UI test passed; the search-position test initially caught insufficient movement, and passed after the heading/spacing correction. These two targeted UI tests passed across separate runs. Full UI suite and physical phone behavior were not rerun. Logs: /tmp/indoorbility-plum-final-build.log, /tmp/indoorbility-plum-ui.log, /tmp/indoorbility-plum-ui-fixed.log.
