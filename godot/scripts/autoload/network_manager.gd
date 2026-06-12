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
const DEFAULT_SIGNALING_URL := "ws://127.0.0.1:9080"
const DEFAULT_ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
]

var is_host := false
var join_code := ""
var signaling_url := DEFAULT_SIGNALING_URL

var _signaling: SignalingClient
var _rtc_peer: WebRTCMultiplayerPeer
var _rtc_connections: Dictionary = {}  # peer_id -> WebRTCPeerConnection
var _ice_servers: Array = DEFAULT_ICE_SERVERS
var _session_announced := false


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- ENet (LAN / direct IP fallback) -----------------------------------------

func host_lan(port: int = DEFAULT_PORT) -> void:
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
	joiner_progress.emit("Looking up game %s..." % code.strip_edges().to_upper())


func _webrtc_available() -> bool:
	# Without the webrtc-native GDExtension, WebRTCPeerConnection.new()
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


func _on_sig_hosted(code: String, peer_id: int, ice_servers: Array) -> void:
	join_code = code
	if not ice_servers.is_empty():
		_ice_servers = ice_servers
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
	var err := conn.initialize({"iceServers": _ice_servers})
	if err != OK:
		session_failed.emit("WebRTC init failed (extension missing?)")
		return
	conn.session_description_created.connect(_on_rtc_description.bind(peer_id, conn))
	conn.ice_candidate_created.connect(_on_rtc_candidate.bind(peer_id))
	_rtc_connections[peer_id] = conn
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
	_rtc_peer = null
	join_code = ""
	is_host = false
	_session_announced = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
