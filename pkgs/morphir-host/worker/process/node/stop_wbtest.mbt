///|
test "a worker that exits by itself reports its exit" {
  debug_inspect(
    stop_result(
      Group,
      GraceExpired,
      NotNeeded,
      before=Some(Exited(code=0)),
      after=None,
    ),
    content="(Exited(code=0), ExitedAfterExit)",
  )
}

///|
test "a stopped tree reports the reason and the tree method" {
  debug_inspect(
    stop_result(
      Group,
      Deadline,
      Stopped,
      before=None,
      after=Some(Signalled(signal=9)),
    ),
    content="(Terminated(Deadline), GroupSignal)",
  )
  debug_inspect(
    stop_result(
      RootTree,
      Cancelled,
      Stopped,
      before=None,
      after=Some(Exited(code=1)),
    ),
    content="(Terminated(Cancelled), TreeTermination)",
  )
}

///|
test "an exited worker whose descendants the host stopped keeps its exit" {
  debug_inspect(
    stop_result(
      Group,
      GraceExpired,
      Stopped,
      before=Some(Exited(code=0)),
      after=None,
    ),
    content="(Exited(code=0), GroupSignal)",
  )
}

///|
test "a worker that exits while the host stops it reports its exit" {
  debug_inspect(
    stop_result(
      Group,
      Fault,
      NotNeeded,
      before=None,
      after=Some(Exited(code=3)),
    ),
    content="(Exited(code=3), ExitedAfterExit)",
  )
}

///|
test "a tree that does not stop is unconfirmed" {
  debug_inspect(
    stop_result(Group, Deadline, Unconfirmed, before=None, after=None),
    content="(Unconfirmed(Deadline), GroupSignal)",
  )
  debug_inspect(
    stop_result(
      RootTree,
      GraceExpired,
      Unconfirmed,
      before=Some(Exited(code=0)),
      after=None,
    ),
    content="(Unconfirmed(GraceExpired), TreeTermination)",
  )
}
