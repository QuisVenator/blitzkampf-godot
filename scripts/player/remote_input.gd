class_name RemoteInput
extends InputSource
## Server-side source for a player controlled from another machine. Packets queue
## up as they arrive and the server consumes one per physics tick, in order, so
## the server simulation sees the same frames the client predicted from (each
## frame carries the client's sequence number, which the server reports back).
## Edge events travel as running counters, so a lost packet can't lose a press.

const PACKET_SIZE := 11
## Without news from the client for this long its player stops acting.
const STALE_MS := 500
## Packets queued beyond this are skipped to catch up after a stall.
const MAX_QUEUE := 4

const HELD_JUMP := 1
const HELD_SPRINT := 2
const HELD_CROUCH := 4
const HELD_FIRE := 8
const HELD_FIRE_SECONDARY := 16
const HELD_AIM := 32

var _queue: Array[PackedFloat32Array] = []
var _last := InputFrame.new()
var _last_sequence := 0
var _last_receive_ms := 0
var _seen: Array[int] = []


## `counts` = running totals of [crouch, reload, interact, interact_alt] presses.
static func pack(frame: InputFrame, counts: Array[int]) -> PackedFloat32Array:
	var held := 0
	held |= HELD_JUMP if frame.jump else 0
	held |= HELD_SPRINT if frame.sprint else 0
	held |= HELD_CROUCH if frame.crouch else 0
	held |= HELD_FIRE if frame.fire else 0
	held |= HELD_FIRE_SECONDARY if frame.fire_secondary else 0
	held |= HELD_AIM if frame.aim else 0
	return PackedFloat32Array([frame.sequence, frame.move.x, frame.move.y, frame.yaw, frame.pitch, held, counts[0], counts[1], counts[2], counts[3], 0.0])


func receive(packet: PackedFloat32Array) -> void:
	if packet.size() != PACKET_SIZE or int(packet[0]) <= _last_sequence:
		return
	_queue.append(packet)
	_last_receive_ms = Time.get_ticks_msec()


func sample(_input: PlayerInput) -> InputFrame:
	if _queue.is_empty():
		# Starved: repeat the last held state, without button presses.
		var repeat := InputFrame.new()
		repeat.sequence = _last_sequence
		repeat.yaw = _last.yaw
		repeat.pitch = _last.pitch
		if Time.get_ticks_msec() - _last_receive_ms <= STALE_MS:
			_copy_held(_last, repeat)
		return repeat

	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	var packet: PackedFloat32Array = _queue.pop_front()
	var frame := _unpack(packet)
	var counts: Array[int] = [int(packet[6]), int(packet[7]), int(packet[8]), int(packet[9])]
	if _seen.is_empty():
		_seen = counts.duplicate()
	# Presses in skipped packets still count: counters only ever grow.
	frame.crouch_pressed = counts[0] > _seen[0]
	frame.reload_pressed = counts[1] > _seen[1]
	frame.interact_pressed = counts[2] > _seen[2]
	frame.interact_alt_pressed = counts[3] > _seen[3]
	_seen = counts
	_last = frame
	_last_sequence = frame.sequence
	return frame


func _unpack(packet: PackedFloat32Array) -> InputFrame:
	var frame := InputFrame.new()
	frame.sequence = int(packet[0])
	frame.move = Vector2(packet[1], packet[2])
	frame.yaw = packet[3]
	frame.pitch = packet[4]
	var held := int(packet[5])
	frame.jump = held & HELD_JUMP != 0
	frame.sprint = held & HELD_SPRINT != 0
	frame.crouch = held & HELD_CROUCH != 0
	frame.fire = held & HELD_FIRE != 0
	frame.fire_secondary = held & HELD_FIRE_SECONDARY != 0
	frame.aim = held & HELD_AIM != 0
	return frame


func _copy_held(from: InputFrame, to: InputFrame) -> void:
	to.move = from.move
	to.jump = from.jump
	to.sprint = from.sprint
	to.crouch = from.crouch
	to.fire = from.fire
	to.fire_secondary = from.fire_secondary
	to.aim = from.aim
