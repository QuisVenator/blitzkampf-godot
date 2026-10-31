class_name NetSim
extends RefCounted
## Artificial network conditions for testing without root (`tc netem` is the
## alternative). Set from the command line by `Net` (`--net-lag=<ms>`,
## `--net-loss=<percent>`) and applied on the *receiving side* of a client: its
## input packets leave late and its state snapshots are processed late, so the
## round trip is twice `lag_ms`.

static var lag_ms := 0
## Probability (0..1) that a packet is dropped.
static var loss := 0.0


static func drops() -> bool:
	return loss > 0.0 and randf() < loss
