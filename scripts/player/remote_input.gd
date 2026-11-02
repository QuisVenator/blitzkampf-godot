class_name RemoteInput
extends InputSource
## Server-side source for a player controlled from another machine. Packets queue
## up as they arrive and the server consumes one per physics tick, in order, so
## the server simulation sees the same frames the client predicted from (each
## frame carries the client's sequence number, which the server reports back).
## Edge events travel as running counters, so a lost packet can't lose a press.

## Layout of a packet (one float each; `SIZE` is the length).
enum Field {
	SEQUENCE, MOVE_X, MOVE_Y, YAW, PITCH,
	HELD,  # bit set of the HELD_* flags below
	CROUCH_COUNT, RELOAD_COUNT, INTERACT_COUNT, INTERACT_ALT_COUNT,
	VIEW_TICK,
	SIZE,
}
## Indices into the running press counters (`pack`'s `counts`), in `Field` order.
enum Count { CROUCH, RELOAD, INTERACT, INTERACT_ALT }
const PACKET_SIZE := Field.SIZE
## Without news from the client for this long its player stops acting.
const STALE_MS := 500
## Packets queued beyond this are skipped to catch up after a stall.
const MAX_QUEUE := 4
## With more than this left after the tick's frame, a second frame is simulated in
## the same tick so a backlog drains instead of becoming permanent delay.
const CATCH_UP_QUEUE := 2

const HELD_JUMP := 1
const HELD_SPRINT := 2
const HELD_CROUCH := 4
const HELD_FIRE := 8
const HELD_FIRE_SECONDARY := 16
const HELD_AIM := 32

var _queue: Array[PackedFloat32Array] = []
var _last := InputFrame.new()
var _last_sequence := 0
var _newest_received := 0
var _last_receive_ms := 0
var _seen: Array[int] = []


## `counts` = running totals of presses, indexed by `Count`.
static func pack(frame: InputFrame, counts: Array[int]) -> PackedFloat32Array:
	var held := 0
	held |= HELD_JUMP if frame.jump else 0
	held |= HELD_SPRINT if frame.sprint else 0
	held |= HELD_CROUCH if frame.crouch else 0
	held |= HELD_FIRE if frame.fire else 0
	held |= HELD_FIRE_SECONDARY if frame.fire_secondary else 0
	held |= HELD_AIM if frame.aim else 0
	return PackedFloat32Array([
		frame.sequence, frame.move.x, frame.move.y, frame.yaw, frame.pitch, held,
		counts[Count.CROUCH], counts[Count.RELOAD], counts[Count.INTERACT], counts[Count.INTERACT_ALT],
		frame.view_tick,
	])


## A packet holds the sender's newest frame, optionally followed by the one before
## it, so a single lost packet costs nothing (the next one repeats the lost frame).
func receive(packet: PackedFloat32Array) -> void:
	if packet.size() != PACKET_SIZE and packet.size() != PACKET_SIZE * 2:
		return
	if packet.size() == PACKET_SIZE * 2:
		_enqueue(packet.slice(PACKET_SIZE))
	_enqueue(packet.slice(0, PACKET_SIZE))
	_last_receive_ms = Time.get_ticks_msec()


func _enqueue(packet: PackedFloat32Array) -> void:
	if int(packet[Field.SEQUENCE]) <= _newest_received:
		return
	_newest_received = int(packet[Field.SEQUENCE])
	_queue.append(packet)


func sample(_input: PlayerInput) -> InputFrame:
	if _queue.is_empty():
		# Starved (a late or lost packet): the body waits, so the server never takes
		# a step the client didn't. Held buttons carry on for the weapons.
		var idle := InputFrame.new()
		idle.idle = true
		idle.sequence = _last_sequence
		idle.yaw = _last.yaw
		idle.pitch = _last.pitch
		if Time.get_ticks_msec() - _last_receive_ms <= STALE_MS:
			_copy_held(_last, idle)
		return idle

	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	return _next_frame()


func extra_frame() -> InputFrame:
	return _next_frame() if _queue.size() > CATCH_UP_QUEUE else null


func _next_frame() -> InputFrame:
	var packet: PackedFloat32Array = _queue.pop_front()
	var frame := _unpack(packet)
	var counts: Array[int] = [
		int(packet[Field.CROUCH_COUNT]), int(packet[Field.RELOAD_COUNT]),
		int(packet[Field.INTERACT_COUNT]), int(packet[Field.INTERACT_ALT_COUNT]),
	]
	if _seen.is_empty():
		_seen = counts.duplicate()
	# Presses in skipped packets still count: counters only ever grow.
	frame.crouch_pressed = counts[Count.CROUCH] > _seen[Count.CROUCH]
	frame.reload_pressed = counts[Count.RELOAD] > _seen[Count.RELOAD]
	frame.interact_pressed = counts[Count.INTERACT] > _seen[Count.INTERACT]
	frame.interact_alt_pressed = counts[Count.INTERACT_ALT] > _seen[Count.INTERACT_ALT]
	_seen = counts
	_last = frame
	_last_sequence = frame.sequence
	return frame


func _unpack(packet: PackedFloat32Array) -> InputFrame:
	var frame := InputFrame.new()
	frame.sequence = int(packet[Field.SEQUENCE])
	frame.move = Vector2(packet[Field.MOVE_X], packet[Field.MOVE_Y])
	frame.yaw = packet[Field.YAW]
	frame.pitch = packet[Field.PITCH]
	frame.view_tick = packet[Field.VIEW_TICK]
	var held := int(packet[Field.HELD])
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
