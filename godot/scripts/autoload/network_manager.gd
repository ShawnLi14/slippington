extends Node
## NetworkManager autoload: owns the multiplayer peer lifecycle for both
## transports. Game code never touches transports directly — it reacts to
## the session signals below, and the high-level multiplayer API (RPCs)
## works identically over ENet (LAN/direct IP) and WebRTC (internet P2P).

signal session_started            # we're in a session (host or joined)
signal session_failed(reason: String)
signal session_closed(reason: String)
signal hosted_online(code: String)
signal joiner_progress(text: String)

const DEFAULT_PORT := 7777
const DEFAULT_SIGNALING_URL := "wss://slippington-signaling.fly.dev"
const DEFAULT_ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
]

var is_host := false
var join_code := ""
var signaling_url := DEFAULT_SIGNALING_URL
## Debug/test only: when true, WebRTC ignores host and server-reflexive
## candidates and connects ONLY through the TURN relay. On a single machine
## two peers would otherwise always pair via host candidates, so this is the
## only way to actually exercise the relay path end to end. Set by the test
## driver's --force-relay flag; never enabled in normal play.
var force_relay := false
## How long a WebRTC connection may sit unconnected before we call it dead.
## A blocked network (VPN, strict NAT, UDP filtered) often leaves ICE stuck
## "connecting" forever instead of reporting failure — without this watchdog
## that looked like an endless spinner with no explanation.
var connect_timeout_sec := 20.0

var _signaling: SignalingClient
var _rtc_peer: WebRTCMultiplayerPeer
var _rtc_connections: Dictionary = {}  # peer_id -> WebRTCPeerConnection
var _connect_deadlines: Dictionary = {}  # peer_id -> local seconds deadline
var _ice_servers: Array = DEFAULT_ICE_SERVERS
var _session_announced := false


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# peer_connected fires when a peer is fully connected at the multiplayer
	# level (all data channels open) — the reliable "connected" signal. We use it
	# to retire the connect watchdog instead of WebRTCPeerConnection's PC-level
	# state, which is unreliable on Web (see _process).
	multiplayer.peer_connected.connect(_on_peer_connected)


func _on_peer_connected(peer_id: int) -> void:
	_connect_deadlines.erase(peer_id)


func _process(_delta: float) -> void:
	# WebRTC connect watchdog (see connect_timeout_sec).
	if _connect_deadlines.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for peer_id in _connect_deadlines.keys():
		var conn: WebRTCPeerConnection = _rtc_connections.get(peer_id)
		if conn == null:
			_connect_deadlines.erase(peer_id)
			continue
		var state := conn.get_connection_state()
		if state == WebRTCPeerConnection.STATE_CONNECTED:
			_connect_deadlines.erase(peer_id)
			continue
		# WebRTCPeerConnection.get_connection_state() is unreliable on the Web
		# platform: it can report FAILED/CLOSED (and never settle on CONNECTED)
		# even while the data channels are open and RPCs flow. Treating that as
		# fatal killed working sessions ~match-start time, so on web we ignore it
		# and rely on the timeout below plus peer_connected clearing the deadline.
		var reported_dead := (state == WebRTCPeerConnection.STATE_FAILED \
				or state == WebRTCPeerConnection.STATE_CLOSED) and not OS.has_feature("web")
		if reported_dead or now > _connect_deadlines[peer_id]:
			_connect_deadlines.erase(peer_id)
			_on_rtc_connect_failed(peer_id, reported_dead)


func _on_rtc_connect_failed(peer_id: int, reported_dead: bool) -> void:
	if is_host:
		# One joiner's network failed — drop the half-open connection but
		# keep the room alive for everyone else in the lobby.
		_on_sig_peer_left(peer_id)
		return
	var why := "Connection failed" if reported_dead else "Connection timed out"
	session_failed.emit(why + " — a VPN or strict network is likely blocking P2P traffic. Try disabling VPNs or switching networks (both players).")
	leave()


# --- ENet (LAN / direct IP fallback) -----------------------------------------

func host_lan(port: int = DEFAULT_PORT) -> void:
	if OS.has_feature("web"):
		# ENet has no HTML5 implementation — browsers can't open raw UDP sockets.
		session_failed.emit("LAN hosting isn't available in the browser — use Create Game.")
		return
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, GameConfig.MAX_PLAYERS)
	if err != OK:
		session_failed.emit("Could not open port %d (in use?)" % port)
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	_announce_session()


func join_lan(ip: String, port: int = DEFAULT_PORT) -> void:
	if OS.has_feature("web"):
		# ENet has no HTML5 implementation — browsers can't open raw UDP sockets.
		session_failed.emit("Direct IP connect isn't available in the browser — use a join code.")
		return
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		session_failed.emit("Invalid address: %s" % ip)
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	joiner_progress.emit("Connecting to %s..." % ip)


# --- WebRTC (internet P2P via join codes) ------------------------------------

func host_online() -> void:
	leave()
	if not _webrtc_available():
		session_failed.emit("WebRTC extension missing — see godot/README.md")
		return
	_start_signaling()
	_signaling.hosted.connect(_on_sig_hosted)
	_signaling.peer_joined.connect(_on_sig_peer_joined)
	_signaling.host_room()
	joiner_progress.emit("Contacting signaling server...")


func join_online(code: String) -> void:
	leave()
	if not _webrtc_available():
		session_failed.emit("WebRTC extension missing — see godot/README.md")
		return
	_start_signaling()
	_signaling.joined.connect(_on_sig_joined)
	_signaling.join_room(code)
	# Remember the code on the joiner side too, so the lobby can show it
	# (everyone in the lobby can recruit more friends, not just the host).
	join_code = code.strip_edges().to_upper()
	joiner_progress.emit("Looking up game %s..." % join_code)


func _webrtc_available() -> bool:
	# On Web, WebRTC is provided by the browser itself (no GDExtension needed),
	# so the class is always usable — skip the probe and the desktop-only
	# "extension missing" messaging it guards.
	if OS.has_feature("web"):
		return true
	# On desktop, without the webrtc-native GDExtension, WebRTCPeerConnection.new()
	# returns a stub whose initialize() fails.
	var test := WebRTCPeerConnection.new()
	return test.initialize() == OK


func _start_signaling() -> void:
	_signaling = SignalingClient.new()
	add_child(_signaling)
	_signaling.sig_error.connect(_on_sig_error)
	_signaling.peer_left.connect(_on_sig_peer_left)
	_signaling.offer_received.connect(_on_sig_offer)
	_signaling.answer_received.connect(_on_sig_answer)
	_signaling.candidate_received.connect(_on_sig_candidate)
	_signaling.connect_to(signaling_url)


## One-line summary of an ice_servers config for the log — makes "did this
## session even have a TURN relay available?" answerable after the fact.
func _describe_ice(servers: Array) -> String:
	var stun := 0
	var turn := 0
	for s in servers:
		var urls = s.get("urls", [])
		if urls is String:
			urls = [urls]
		for u in urls:
			if str(u).begins_with("turn"):
				turn += 1
			elif str(u).begins_with("stun"):
				stun += 1
	return "%d STUN / %d TURN urls" % [stun, turn]


func _on_sig_hosted(code: String, peer_id: int, ice_servers: Array) -> void:
	join_code = code
	if not ice_servers.is_empty():
		_ice_servers = ice_servers
	print("[net] ICE config: " + _describe_ice(_ice_servers))
	_rtc_peer = WebRTCMultiplayerPeer.new()
	_rtc_peer.create_server()
	multiplayer.multiplayer_peer = _rtc_peer
	is_host = true
	hosted_online.emit(code)
	_announce_session()
	assert(peer_id == 1)


func _on_sig_joined(peer_id: int, host_id: int, ice_servers: Array) -> void:
	if not ice_servers.is_empty():
		_ice_servers = ice_servers
	print("[net] ICE config: " + _describe_ice(_ice_servers))
	_rtc_peer = WebRTCMultiplayerPeer.new()
	_rtc_peer.create_client(peer_id)
	multiplayer.multiplayer_peer = _rtc_peer
	is_host = false
	# The host creates the offer; we just prepare the connection object.
	_create_rtc_connection(host_id, false)
	joiner_progress.emit("Connecting to host...")


func _on_sig_peer_joined(peer_id: int) -> void:
	# Host side: a joiner appeared — open a connection and send the offer.
	_create_rtc_connection(peer_id, true)


func _create_rtc_connection(peer_id: int, make_offer: bool) -> void:
	var conn := WebRTCPeerConnection.new()
	var config := {"iceServers": _ice_servers}
	if force_relay:
		config["iceTransportPolicy"] = "relay"
	var err := conn.initialize(config)
	if err != OK:
		session_failed.emit("WebRTC init failed (extension missing?)")
		return
	conn.session_description_created.connect(_on_rtc_description.bind(peer_id, conn))
	conn.ice_candidate_created.connect(_on_rtc_candidate.bind(peer_id))
	_rtc_connections[peer_id] = conn
	_connect_deadlines[peer_id] = Time.get_ticks_msec() / 1000.0 + connect_timeout_sec
	_rtc_peer.add_peer(conn, peer_id)
	if make_offer:
		conn.create_offer()


func _on_rtc_description(type: String, sdp: String, peer_id: int, conn: WebRTCPeerConnection) -> void:
	conn.set_local_description(type, sdp)
	if _signaling == null:
		return
	if type == "offer":
		_signaling.send_offer(peer_id, sdp)
	else:
		_signaling.send_answer(peer_id, sdp)


func _on_rtc_candidate(media: String, index: int, sdp: String, peer_id: int) -> void:
	if _signaling != null:
		_signaling.send_candidate(peer_id, media, index, sdp)


func _on_sig_offer(from_id: int, sdp: String) -> void:
	if _rtc_connections.has(from_id):
		# Setting the remote offer makes the connection emit an answer
		# via session_description_created.
		_rtc_connections[from_id].set_remote_description("offer", sdp)


func _on_sig_answer(from_id: int, sdp: String) -> void:
	if _rtc_connections.has(from_id):
		_rtc_connections[from_id].set_remote_description("answer", sdp)


func _on_sig_candidate(from_id: int, media: String, index: int, sdp: String) -> void:
	if _rtc_connections.has(from_id):
		_rtc_connections[from_id].add_ice_candidate(media, index, sdp)


func _on_sig_peer_left(peer_id: int) -> void:
	# Signaling only brokers connection SETUP. Once a peer is fully connected at
	# the multiplayer level, its P2P link is independent of signaling — so ignore
	# a signaling "peer left" for it. Otherwise tearing the signaling room down
	# (the host closes signaling when the match starts, and the server then tells
	# every joiner the host left) would drop live game connections mid-match.
	# Genuine P2P drops are handled by multiplayer.peer_disconnected instead.
	if peer_id in multiplayer.get_peers():
		return
	if _rtc_connections.has(peer_id):
		_rtc_peer.remove_peer(peer_id)
		_rtc_connections.erase(peer_id)


func _on_sig_error(reason: String) -> void:
	if not _session_announced:
		session_failed.emit(reason)
		leave()


## Lobby is over — late joiners no longer accepted, signaling not needed.
func close_signaling() -> void:
	if _signaling != null:
		_signaling.close()
		_signaling.queue_free()
		_signaling = null


# --- shared session plumbing --------------------------------------------------

func _announce_session() -> void:
	_session_announced = true
	session_started.emit()
	GameState.enter_lobby()


func _on_connected_to_server() -> void:
	# Client side: connection to host established (ENet or WebRTC).
	_announce_session()


func _on_connection_failed() -> void:
	session_failed.emit("Could not connect to host")
	leave()


func _on_server_disconnected() -> void:
	session_closed.emit("Host left the game")
	leave()
	GameState.reset_to_menu("Host left the game")


func leave() -> void:
	close_signaling()
	for conn in _rtc_connections.values():
		conn.close()
	_rtc_connections.clear()
	_connect_deadlines.clear()
	_rtc_peer = null
	join_code = ""
	is_host = false
	_session_announced = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
