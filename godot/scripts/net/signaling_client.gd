class_name SignalingClient
extends Node
## WebSocket client for the signaling server in signaling/server.js.
## Speaks the tiny JSON protocol used to broker WebRTC connections:
## host/join with a 5-char room code, then relay SDP offers/answers and
## ICE candidates between peers. Carries no gameplay traffic.

signal hosted(code: String, peer_id: int, ice_servers: Array)
signal joined(peer_id: int, host_id: int, ice_servers: Array)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal offer_received(from_id: int, sdp: String)
signal answer_received(from_id: int, sdp: String)
signal candidate_received(from_id: int, media: String, index: int, sdp: String)
signal sig_error(reason: String)
signal closed

const CONNECT_TIMEOUT_SEC := 10.0

var _ws: WebSocketPeer
var _was_open := false
var _pending_send: Array[String] = []
var _connecting_for := 0.0


func connect_to(url: String) -> Error:
	_ws = WebSocketPeer.new()
	_was_open = false
	_connecting_for = 0.0
	var err := _ws.connect_to_url(url)
	if err != OK:
		sig_error.emit("Could not reach signaling server")
	return err


func close() -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close()
	_ws = null
	_pending_send.clear()


func host_room() -> void:
	_send({"type": "host"})


func join_room(code: String) -> void:
	_send({"type": "join", "code": code.strip_edges().to_upper()})


func send_offer(to_id: int, sdp: String) -> void:
	_send({"type": "offer", "to": to_id, "data": sdp})


func send_answer(to_id: int, sdp: String) -> void:
	_send({"type": "answer", "to": to_id, "data": sdp})


func send_candidate(to_id: int, media: String, index: int, sdp: String) -> void:
	_send({"type": "candidate", "to": to_id, "data": {"media": media, "index": index, "sdp": sdp}})


func _send(msg: Dictionary) -> void:
	var text := JSON.stringify(msg)
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(text)
	else:
		_pending_send.append(text)


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_connecting_for += delta
		if _connecting_for > CONNECT_TIMEOUT_SEC:
			_ws.close()
			_ws = null
			sig_error.emit("Signaling server not responding — try again")
			return
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			for text in _pending_send:
				_ws.send_text(text)
			_pending_send.clear()
		# A message handler can tear this client down mid-loop (an error
		# reply makes NetworkManager close us synchronously) — re-check _ws
		# every iteration or this dereferences null.
		while _ws != null and _ws.get_available_packet_count() > 0:
			_handle_message(_ws.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		var had_ws := _ws != null
		_ws = null
		if had_ws:
			if _was_open:
				closed.emit()
			else:
				sig_error.emit("Could not reach signaling server")


func _handle_message(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if msg == null or not msg is Dictionary:
		return
	match msg.get("type", ""):
		"hosted":
			hosted.emit(msg["code"], int(msg["peer_id"]), msg.get("ice_servers", []))
		"joined":
			joined.emit(int(msg["peer_id"]), int(msg["host_id"]), msg.get("ice_servers", []))
		"peer_joined":
			peer_joined.emit(int(msg["peer_id"]))
		"peer_left":
			peer_left.emit(int(msg["peer_id"]))
		"offer":
			offer_received.emit(int(msg["from"]), str(msg["data"]))
		"answer":
			answer_received.emit(int(msg["from"]), str(msg["data"]))
		"candidate":
			var d: Dictionary = msg["data"]
			candidate_received.emit(int(msg["from"]), str(d["media"]), int(d["index"]), str(d["sdp"]))
		"error":
			sig_error.emit(str(msg.get("reason", "unknown signaling error")))
