///|
/// A reply to a bounded generation request or its cancellation.
#derive(Eq, Debug)
pub(all) enum GenerationReply {
  Stepped(@model_access.GenerationStep)
  CancelledGeneration(@model_access.Cancel)
}

///|
pub extend GenerationReply with Eq::{equal, not_equal}

///|
pub extend GenerationReply with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub struct GenerationAnswer {
  class : OutcomeClass[GenerationReply]
  diagnostics : Array[Diagnostic]
}

///|
pub extend GenerationAnswer with Eq::{equal, not_equal}

///|
pub extend GenerationAnswer with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
priv struct GenerationRun {
  session_id : String
  snapshot_id : String
  limits : @model_access.Limits
  round : Int32
  requests : Array[@model_access.ReadRequest]
  request_ids : Array[String]
}

///|
#derive(Eq, Debug)
priv enum PendingGeneration {
  Next(GenerationRun, Int64)
  Cancel(GenerationRun)
}

///|
fn PendingGeneration::run(self : PendingGeneration) -> GenerationRun {
  match self {
    Next(run, _) | Cancel(run) => run
  }
}

///|
fn Conversation::generation_refusal(
  self : Conversation,
  code : RefusalCode,
  message : String,
) -> (Conversation, Step) {
  (
    self,
    BoundedAnswered(sends=[], {
      class: Refused(code~, message~),
      diagnostics: [],
    }),
  )
}

///|
fn Conversation::send_generation(
  self : Conversation,
  pending : PendingGeneration,
  method_name : String,
  params : Json,
) -> (Conversation, Step) {
  let id = self.next_id
  let message = Message::new({
    "jsonrpc": "2.0",
    "id": id,
    "method": method_name,
    "params": params,
  })
  let size = framed_size(message.size())
  let ceiling = pending.run().limits.frame_bytes()
  guard size.to_int64() <= ceiling && id < 2147483647 else {
    return self.generation_refusal(
      RequestLimit,
      "the bounded request exceeds the frame limit or request ID space",
    )
  }
  let used = if pending is Next(run, 1L) {
    [..self.used_generation_ids, run.session_id]
  } else {
    self.used_generation_ids
  }
  (
    {
      ..self,
      phase: CallingGeneration(pending),
      pending: id,
      next_id: id + 1,
      used_generation_ids: used,
    },
    Exchange(sends=[message], awaiting=id),
  )
}

///|
/// Starts a new operation only after live draft.2 admission.
pub fn Conversation::start_generation(
  self : Conversation,
  request : @model_access.Start,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready else {
    raise SessionUnavailable("the session is not ready for generation")
  }
  guard self.negotiated is Some({ model_access: Some(access), .. }) &&
    self.expected is Some(claims) else {
    return self.generation_refusal(
      ProtocolUnavailable,
      "bounded access was not admitted",
    )
  }
  guard self.generation is None &&
    !self.used_generation_ids.contains(request.session_id) else {
    return self.generation_refusal(
      AgreementMismatch,
      "the generation ID is active or has already been used",
    )
  }
  guard access.tuples().contains(request.input) else {
    return self.generation_refusal(
      TupleUnavailable,
      "the requested bounded tuple was not agreed",
    )
  }
  guard claims.targets
    .iter()
    .any(target => target.to_string() == request.target) else {
    return self.generation_refusal(
      CapabilityUnavailable,
      "the worker did not claim this generation target",
    )
  }
  guard request.limits.at_most(access.limits) else {
    return self.generation_refusal(
      RequestLimit,
      "the start raises an agreed limit",
    )
  }
  let run : GenerationRun = {
    session_id: request.session_id,
    snapshot_id: request.snapshot.snapshot_id,
    limits: request.limits,
    round: 0,
    requests: [],
    request_ids: [],
  }
  self.send_generation(Next(run, 1L), @model_access.START, request.to_json())
}

///|
fn GenerationRun::accepts(
  self : GenerationRun,
  advance : @model_access.Advance,
) -> Bool {
  guard self.session_id == advance.session_id &&
    self.round == advance.round &&
    self.requests.length() == advance.deliveries.length() else {
    return false
  }
  for i, request in self.requests {
    let delivery = advance.deliveries[i]
    let document_id = match request {
      @model_access.ReadRequest::Inventory(..) => None
      @model_access.ReadRequest::Document(document_id~, ..) => Some(document_id)
    }
    if delivery.request_id() != request.request_id() ||
      delivery.snapshot_id() != self.snapshot_id ||
      delivery.document_id() != document_id {
      return false
    }
  }
  true
}

///|
/// An invalid advance consumes neither the pending delivery list nor a wire ID.
pub fn Conversation::advance_generation(
  self : Conversation,
  request : @model_access.Advance,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready else {
    raise SessionUnavailable("there is another exchange in flight")
  }
  guard self.generation is Some(run) && run.accepts(request) else {
    return self.generation_refusal(
      AgreementMismatch,
      "the advance does not match the active session, round or requests",
    )
  }
  self.send_generation(
    Next(run, request.round.to_int64() + 1L),
    @model_access.ADVANCE,
    request.to_json(),
  )
}

///|
pub fn Conversation::cancel_generation(
  self : Conversation,
  request : @model_access.Cancel,
) -> (Conversation, Step) raise SessionUnavailable {
  guard self.phase is Ready else {
    raise SessionUnavailable("there is another exchange in flight")
  }
  guard self.generation is Some(run) && run.session_id == request.session_id else {
    return self.generation_refusal(
      AgreementMismatch,
      "the cancellation names no active generation",
    )
  }
  self.send_generation(Cancel(run), @model_access.CANCEL, request.to_json())
}

///|
fn Conversation::bad_generation_reply(
  self : Conversation,
  message : String,
) -> (Conversation, Step) {
  self.over(
    Abort(Fault),
    EndedEarly(Failed(Host(code=UnexpectedResponse, message~))),
  )
}

///|
fn Conversation::generation_reply(
  self : Conversation,
  pending : PendingGeneration,
  reply : Reply,
) -> (Conversation, Step) {
  match reply {
    GuestError(code~, message~, data~) => {
      let fault : Fault = Guest(code~, message~, data~)
      if pending is Cancel(_) {
        return self.over(Abort(Fault), EndedEarly(Failed(fault)))
      }
      (
        { ..self, phase: Ready, pending: 0, },
        BoundedAnswered(sends=[], { class: Failed(fault), diagnostics: [], }),
      )
    }
    Answer(value) => {
      let run = pending.run()
      match pending {
        Cancel(_) => {
          let acknowledgement = @model_access.Cancel::from_json(value) catch {
            _ =>
              return self.bad_generation_reply(
                "invalid bounded cancellation acknowledgement",
              )
          }
          guard acknowledgement.session_id == run.session_id else {
            return self.bad_generation_reply(
              "cancellation acknowledgement names another generation",
            )
          }
          (
            { ..self, phase: Ready, pending: 0, generation: None, },
            BoundedAnswered(sends=[], {
              class: Completed(CancelledGeneration(acknowledgement)),
              diagnostics: [],
            }),
          )
        }
        Next(_, expected_round) => {
          let step = @model_access.GenerationStep::from_json(value) catch {
            @model_wire.Invalid(code, detail) =>
              return self.bad_generation_reply(
                "invalid generation result: \{code}: \{detail}",
              )
          }
          guard step.session_id() == run.session_id else {
            return self.bad_generation_reply(
              "generation result names another session",
            )
          }
          let diagnostics = step.diagnostics()
          guard diagnostics.length() <= run.limits.diagnostics_per_exchange() else {
            return self.bad_generation_reply(
              "generation result exceeds the diagnostics limit",
            )
          }
          let diagnostics = diagnostics.map(Diagnostic::decode) catch {
            error =>
              return self.bad_generation_reply(
                "invalid generation diagnostic: \{error}",
              )
          }
          let generation = match step {
            @model_access.GenerationStep::Continue(round~, requests~, ..) => {
              guard round.to_int64() == expected_round &&
                round <= run.limits.rounds() else {
                return self.bad_generation_reply(
                  "generation continuation has a stale or out-of-bounds round",
                )
              }
              guard requests.length() <= run.limits.outstanding_requests() else {
                return self.bad_generation_reply(
                  "generation continuation exceeds the outstanding request limit",
                )
              }
              let new_ids : Array[String] = []
              for request in requests {
                let id = request.request_id()
                guard !run.request_ids.contains(id) && !new_ids.contains(id) else {
                  return self.bad_generation_reply(
                    "generation continuation repeats a request ID",
                  )
                }
                new_ids.push(id)
              }
              Some({
                ..run,
                round,
                requests: [..requests],
                request_ids: [..run.request_ids, ..new_ids],
              })
            }
            _ => None
          }
          (
            { ..self, phase: Ready, pending: 0, generation, },
            BoundedAnswered(sends=[], {
              class: Completed(Stepped(step)),
              diagnostics,
            }),
          )
        }
      }
    }
  }
}
