local ADDON, S = ...

-- Flight times shipped with Sundry (seconds), by route: "n<from node ID>><to node ID>", or the positions of
-- both nodes on the flight map when the client has no node IDs. Measured routes of your own always win.
-- New entries come from "/sundry flights", which lists the routes you have flown in this format.
S.FLIGHT_DATA = {
}
