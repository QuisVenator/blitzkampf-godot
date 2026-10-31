class_name RemoteInput
extends InputSource
## Server-side source for a player controlled from another machine: serves the
## newest `InputFrame` packet that peer sent. Edge events travel as running
## counters, so a lost packet can't lose a button press.

const PACKET_SIZE := 10
## Without news from the client for this long its player stops acting.
const STALE_MS := 500

const HELD_JUMP := 1
const HELD_SPRINT := 2
const HELD_CROUCH := 4
const HELD_FIRE := 8
const HELD_FIRE_SECONDARY := 16
const HELD_AIM := 32

var _packet := PackedFloat32Array()
var _last_receive_ms := 0
var _seen: Array[int] = []


## `counts` = running totals of [crouch, reload, interact, interact_alt] presses.
static func pack(sequence: int, frame: InputFrame, counts: Array[int]) -> PackedFloat32Array:
	var held := 0
	held |= HELD_JUMP if frame.jump else 0
	held |= HELD_SPRINT if frame.sprint else 0
	held |= HELD_CROUCH if frame.crouch else 0
	held |= HELD_FIRE if frame.fire else 0
	held |= HELD_FIRE_SECONDARY if frame.fire_secondary else 0
	held |= HELD_AIM if frame.aim else 0
	return PackedFloat32Array([sequence, frame.move.x, frame.move.y, frame.yaw, frame.pitch, held, counts[0], counts[1], counts[2], counts[3]])


func receive(packet: PackedFloat32Array) -> void:
	if packet.size() != PACKET_SIZE:
		return
	_packet = packet
	_last_receive_ms = Time.get_ticks_msec()


func sample(_input: PlayerInput) -> InputFrame:
	var frame := InputFrame.new()
	if _packet.is_empty():
		return frame
	frame.yaw = _packet[3]
	frame.pitch = _packet[4]
	if Time.get_ticks_msec() - _last_receive_ms > STALE_MS:
		return frame

	frame.move = Vector2(_packet[1], _packet[2])
	var held := int(_packet[5])
	frame.jump = held & HELD_JUMP != 0
	frame.sprint = held & HELD_SPRINT != 0
	frame.crouch = held & HELD_CROUCH != 0
	frame.fire = held & HELD_FIRE != 0
	frame.fire_secondary = held & HELD_FIRE_SECONDARY != 0
	frame.aim = held & HELD_AIM != 0

	var counts: Array[int] = [int(_packet[6]), int(_packet[7]), int(_packet[8]), int(_packet[9])]
	if _seen.is_empty():
		_seen = counts.duplicate()
	frame.crouch_pressed = counts[0] > _seen[0]
	frame.reload_pressed = counts[1] > _seen[1]
	frame.interact_pressed = counts[2] > _seen[2]
	frame.interact_alt_pressed = counts[3] > _seen[3]
	_seen = counts
	return frame
