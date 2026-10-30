///|
/// How long a worker has to stop by itself after `exit`. After it, the host
/// stops the worker's process tree.
pub const EXIT_GRACE_MS : Int32 = 2000

///|
/// How long the host waits to confirm that a stopped tree is gone. When the
/// bound passes, the stop is unconfirmed.
pub const STOP_CONFIRM_MS : Int32 = 5000
