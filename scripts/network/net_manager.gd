extends Node
## Каркас сетевой части. Авторитетный сервер + клиентское предсказание.
## Это набросок под домашний сервер: API зафиксирован, реализацию наращиваем.

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal server_started(port: int, max_players: int)
signal join_failed(reason: String)

const DEFAULT_PORT := 7777
const MAX_PACKET_RATE := 0
const TICK_RATE := 60.0

var is_server := false
var peers := {}                    # id -> {name, ping_ms, state}
var _peer := ENetMultiplayerPeer.new()


func host(port: int = DEFAULT_PORT, max_players: int = 16) -> Error:
	var err := _peer.create_server(port, max_players)
	if err != OK:
		join_failed.emit("не удалось поднять сервер (%s)" % error_string(err))
		return err
	_peer.set_transfer_mode(ENetMultiplayerPeer.TRANSFER_MODE_RELIABLE)
	multiplayer.multiplayer_peer = _peer
	is_server = true
	for c in _peer.get_host(): pass
	server_started.emit(port, max_players)
	multiplayer.peer_connected.connect(_on_connected)
	multiplayer.peer_disconnected.connect(_on_disconnected)
	print("[net] hosting on :%d, %d слотов" % [port, max_players])
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var err := _peer.create_client(address, port)
	if err != OK:
		join_failed.emit(error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	is_server = false
	multiplayer.connected_to_server.connect(func(): print("[net] connected"))
	multiplayer.connection_failed.connect(func(): join_failed.emit("connection_failed"))
	multiplayer.server_disconnected.connect(_on_server_gone)
	return OK


func leave() -> void:
	multiplayer.multiplayer_peer = null
	is_server = false
	peers.clear()


func _on_connected(id: int) -> void:
	peers[id] = {"name": "player_%d" % id, "ping_ms": 0, "state": "connecting"}
	peer_connected.emit(id)
	# TODO: handshake -> spawn игрока -> сплавить состояние мира


func _on_disconnected(id: int) -> void:
	peers.erase(id)
	peer_disconnected.emit(id)


func _on_server_gone() -> void:
	leave()


func physics_tick() -> void:
	## Вызывается сервером из game_rules. Сюда ляжет снапшот-репликация:
	## position/velocity/аннимация -> 20 Hz, события (выстрел/попадание) -> reliable.
	pass
